---
description: Restate requirements, assess risks, and create step-by-step implementation plan. WAIT for user CONFIRM before touching any code.
---

# Plan Command

This command invokes the **planner** agent to create a comprehensive implementation plan before writing any code.

## What This Command Does

1. **Restate Requirements** - Clarify what needs to be built
2. **Identify Risks** - Surface potential issues and blockers
3. **Create Step Plan** - Break down implementation into phases
4. **Wait for Confirmation** - MUST receive user approval before proceeding

## When to Use

Use `/plan` when:

- Starting a new feature
- Making significant architectural changes
- Working on complex refactoring
- Multiple files/components will be affected
- Requirements are unclear or ambiguous

## How It Works

The planner agent will:

1. **Analyze the request** and restate requirements in clear terms
2. **Break down into phases** with specific, actionable steps
3. **Identify dependencies** between components
4. **Assess risks** and potential blockers
5. **Estimate complexity** (High/Medium/Low)
6. **Present the plan** and WAIT for your explicit confirmation

## Example Usage

```
User: /plan Add order notification when payment is processed

Agent (planner):
# Implementation Plan: Order Notification on Payment Processed

## Requirements Restatement
- Publish a domain event when payment is processed for an order
- Persist notifications to PostgreSQL via R2DBC
- Expose GET /api/notifications/{userId} with pagination
- Consume payment events from Kafka reactively

## Implementation Phases

### Phase 1: Domain Events
- Create `PaymentProcessedEvent` record in `src/main/java/com/example/order/domain/event/`
- Create `OrderNotification` entity in `src/main/java/com/example/notification/domain/`
- Define `NotificationRepository` port (interface) in domain layer

### Phase 2: Notification Service
- Create `NotificationService` in `src/main/java/com/example/notification/application/`
- Implement reactive Kafka consumer (`@KafkaListener`) in infrastructure layer
- Implement `R2dbcNotificationRepository` adapter in `src/main/java/com/example/notification/infrastructure/`
- Wire R2DBC schema migration via Flyway (`V2__create_notifications.sql`)

### Phase 3: REST Endpoint
- Create `NotificationController` in `src/main/java/com/example/notification/interfaces/`
- Implement `GET /api/notifications/{userId}` returning `Flux<NotificationDto>` with pagination
- Add `@Valid` request parameter validation and structured error responses

### Phase 4: Integration Tests
- Testcontainers setup: PostgreSQL + Kafka in `src/test/java/com/example/notification/`
- `NotificationServiceIntegrationTest` using `StepVerifier`
- Contract test for `GET /api/notifications/{userId}` with `WebTestClient`

## Dependencies
- Spring Kafka (reactive consumer)
- R2DBC PostgreSQL driver
- Flyway for schema migration
- Testcontainers (PostgreSQL + Kafka)

## Risks
- HIGH: Kafka consumer offset management — ensure idempotent processing with deduplication key
- MEDIUM: R2DBC connection pool sizing — tune `spring.r2dbc.pool.max-size` under load
- MEDIUM: Notification backlog if consumer falls behind — configure DLT and monitoring
- LOW: Pagination cursor design for high-volume users

## Estimated Complexity: MEDIUM
- Domain + infrastructure: 3-4 hours
- REST endpoint: 1-2 hours
- Integration tests: 2-3 hours
- Total: 6-9 hours

**WAITING FOR CONFIRMATION**: Proceed with this plan? (yes/no/modify)
```

## Important Notes

**CRITICAL**: The planner agent will **NOT** write any code until you explicitly confirm the plan with "yes" or "
proceed" or similar affirmative response.

If you want changes, respond with:

- "modify: [your changes]"
- "different approach: [alternative]"
- "skip phase 2 and do phase 3 first"

## Integration with Other Commands

After planning:

- Run `/spec` to define behavioral contracts before writing code
- Use `/build-fix` if build errors occur
- Use `/code-review` to review completed implementation
