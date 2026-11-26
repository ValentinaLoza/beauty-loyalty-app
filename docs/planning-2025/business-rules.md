# Business Rules

## Authorization
Register/redeem: owner, admin, employee.
Client cannot modify loyalty data.

## Multi-business
All related entities must belong to the same business.

## Loyalty Ledger
Balance = `SUM(points_delta)`.

## Reward Issuance
When balance reaches the target:
- create reward;
- create negative `reward_issued` transaction;
- client immediately starts a new loyalty cycle.

## Multiple Rewards
If enough points exist, one operation may issue multiple rewards.

## Redeemed Service Points
A service using a reward still earns its configured loyalty points.

## Idempotency
`service_records.idempotency_key` prevents duplicate retries.

## Concurrency
Critical operations lock the client row with `FOR UPDATE`.
Redemptions also lock the reward row.
Lock order is always client → reward.

## Historical Snapshots
Past service/reward data is never recalculated after configuration changes.

## Audit
Critical operations store `registered_by`, `created_by`, or `redeemed_by`.

## Deletion
Historical records are not normally deleted.

## Reversal
Future `void_service()` must create reversal transactions instead of deleting originals.
