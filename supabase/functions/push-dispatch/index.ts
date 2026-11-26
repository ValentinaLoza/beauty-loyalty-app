import { withSupabase } from 'npm:@supabase/server@1.4.1'
import {
  buildPushPayload,
} from 'npm:@block65/webcrypto-web-push@1.0.2'

type WebhookPayload = {
  type?: string
  table?: string
  schema?: string
  record?: {
    id?: string
  } | null
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)
  if (!value) {
    throw new Error(`Missing secret: ${name}`)
  }
  return value
}

export default {
  fetch: withSupabase(
    { auth: 'secret' },
    async (req, ctx) => {
      try {
        const webhook =
          (await req.json()) as WebhookPayload

        const outboxId = webhook?.record?.id

        if (!outboxId) {
          return Response.json(
            { error: 'OUTBOX_ID_MISSING' },
            { status: 400 },
          )
        }

        const { data: event, error: eventError } =
          await ctx.supabaseAdmin
            .from('notification_outbox')
            .select('*')
            .eq('id', outboxId)
            .maybeSingle()

        if (eventError) throw eventError

        if (!event) {
          return Response.json(
            { ignored: true, reason: 'NOT_FOUND' },
            { status: 200 },
          )
        }

        if (event.processed_at) {
          return Response.json(
            { ignored: true, reason: 'ALREADY_PROCESSED' },
            { status: 200 },
          )
        }

        if (
          event.scheduled_for &&
          new Date(event.scheduled_for).getTime() >
            Date.now() + 10_000
        ) {
          return Response.json(
            { ignored: true, reason: 'NOT_DUE_YET' },
            { status: 202 },
          )
        }

        let bindingsQuery =
          ctx.supabaseAdmin
            .from('push_bindings')
            .select(
              'id, endpoint_id, client_id, admin_user_id',
            )
            .eq('business_id', event.business_id)
            .eq('enabled', true)

        if (event.audience === 'client') {
          bindingsQuery = bindingsQuery
            .eq('recipient_kind', 'client')
            .eq('client_id', event.client_id)
        } else {
          bindingsQuery = bindingsQuery
            .eq('recipient_kind', 'admin')
        }

        const {
          data: bindings,
          error: bindingsError,
        } = await bindingsQuery

        if (bindingsError) throw bindingsError

        const endpointIds = Array.from(
          new Set(
            (bindings ?? [])
              .map((row) => row.endpoint_id)
              .filter(Boolean),
          ),
        )

        if (endpointIds.length === 0) {
          await ctx.supabaseAdmin
            .from('notification_delivery_log')
            .insert({
              outbox_id: event.id,
              endpoint_id: null,
              status: 'no_subscription',
              error_message:
                'No enabled push subscription for recipient',
            })

          await ctx.supabaseAdmin
            .from('notification_outbox')
            .update({
              processed_at:
                new Date().toISOString(),
              delivered_count: 0,
              failed_count: 0,
            })
            .eq('id', event.id)

          return Response.json({
            processed: true,
            delivered: 0,
            failed: 0,
          })
        }

        const {
          data: endpoints,
          error: endpointError,
        } = await ctx.supabaseAdmin
          .from('push_endpoints')
          .select('*')
          .in('id', endpointIds)
          .eq('enabled', true)

        if (endpointError) throw endpointError

        const vapid = {
          subject: requiredEnv('VAPID_SUBJECT'),
          publicKey:
            requiredEnv('VAPID_PUBLIC_KEY'),
          privateKey:
            requiredEnv('VAPID_PRIVATE_KEY'),
        }

        let delivered = 0
        let failed = 0

        for (const endpoint of endpoints ?? []) {
          try {
            const subscription = {
              endpoint: endpoint.endpoint,
              expirationTime: null,
              keys: {
                p256dh: endpoint.p256dh_key,
                auth: endpoint.auth_key,
              },
            }

            const payload = await buildPushPayload(
              {
                data: {
                  title: event.title,
                  body: event.body,
                  url: event.target_path,
                  tag: event.dedupe_key,
                },
                options: {
                  ttl: 60 * 60 * 24,
                  urgency: 'normal',
                },
              },
              subscription,
              vapid,
            )

            const response = await fetch(
              endpoint.endpoint,
              payload,
            )

            if (response.ok) {
              delivered += 1

              await ctx.supabaseAdmin
                .from('push_endpoints')
                .update({
                  failure_count: 0,
                  last_success_at:
                    new Date().toISOString(),
                  enabled: true,
                })
                .eq('id', endpoint.id)

              await ctx.supabaseAdmin
                .from('notification_delivery_log')
                .insert({
                  outbox_id: event.id,
                  endpoint_id: endpoint.id,
                  http_status: response.status,
                  status: 'sent',
                })
            } else {
              failed += 1
              const expired =
                response.status === 404 ||
                response.status === 410

              await ctx.supabaseAdmin
                .from('push_endpoints')
                .update({
                  enabled:
                    expired
                      ? false
                      : endpoint.enabled,
                  failure_count:
                    (endpoint.failure_count ?? 0) + 1,
                })
                .eq('id', endpoint.id)

              await ctx.supabaseAdmin
                .from('notification_delivery_log')
                .insert({
                  outbox_id: event.id,
                  endpoint_id: endpoint.id,
                  http_status: response.status,
                  status:
                    expired ? 'expired' : 'failed',
                  error_message:
                    await response.text(),
                })
            }
          } catch (error) {
            failed += 1

            await ctx.supabaseAdmin
              .from('push_endpoints')
              .update({
                failure_count:
                  (endpoint.failure_count ?? 0) + 1,
              })
              .eq('id', endpoint.id)

            await ctx.supabaseAdmin
              .from('notification_delivery_log')
              .insert({
                outbox_id: event.id,
                endpoint_id: endpoint.id,
                status: 'failed',
                error_message:
                  error instanceof Error
                    ? error.message
                    : String(error),
              })
          }
        }

        await ctx.supabaseAdmin
          .from('notification_outbox')
          .update({
            processed_at:
              new Date().toISOString(),
            delivered_count: delivered,
            failed_count: failed,
          })
          .eq('id', event.id)

        return Response.json({
          processed: true,
          delivered,
          failed,
        })
      } catch (error) {
        console.error(error)

        return Response.json(
          {
            error:
              error instanceof Error
                ? error.message
                : String(error),
          },
          { status: 500 },
        )
      }
    },
  ),
}
