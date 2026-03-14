---
name: hexagonal-arch
description: >
  Comprehensive Hexagonal Architecture (Ports and Adapters) patterns for Java
  Spring WebFlux applications. Covers package structure, dependency rules, port/adapter
  design, domain modeling, mapping strategies, CQRS integration, testing strategy,
  and real-world examples. Use when designing or refactoring Spring Boot 3.x projects
  with clean architecture principles.
version: 1.0.0
---

# Hexagonal Architecture for Spring WebFlux

Production-ready Hexagonal Architecture patterns for Java 17+ / Spring Boot 3.x reactive applications.

## Quick Reference

| Category | When to Use | Jump To |
|----------|------------|---------|
| Core Concepts | Understanding ports, adapters, domain | [Core Concepts](#core-concepts) |
| Package Structure | Setting up a new project | [Package Structure](#package-structure) |
| Dependency Rules | Enforcing boundaries | [Dependency Rules](#dependency-rules) |
| Domain Layer | Entities, Value Objects, Domain Events | [Domain Layer](#domain-layer) |
| Application Layer | Use Cases, Input/Output Ports | [Application Layer](#application-layer) |
| Infrastructure | REST, DB, Kafka adapters | [Infrastructure Layer](#infrastructure-layer) |
| Mapping Strategy | Entity ↔ Domain ↔ DTO | [Mapping Strategy](#mapping-strategy) |
| Testing | Unit, Integration, E2E | [Testing Strategy](#testing-strategy) |
| CQRS Integration | Command/Query separation | [CQRS Integration](#cqrs-integration) |
| When to Use | Decision guide | [When to Use](#when-to-use-vs-when-overkill) |
| Real-World Example | Full Order Service | [Example](#real-world-example-order-service) |
| Anti-Patterns | Common mistakes | [Anti-Patterns](#anti-patterns) |

---

## Core Concepts

### What is Hexagonal Architecture?

Hexagonal Architecture (Ports and Adapters), introduced by Alistair Cockburn, isolates business logic from external concerns (frameworks, databases, APIs). The domain is at the center; everything else plugs in through defined interfaces.

```
          ┌──────────────────────────────────────────┐
          │            Infrastructure                 │
          │  ┌──────────────────────────────────┐     │
          │  │         Application               │    │
          │  │  ┌──────────────────────────┐     │    │
          │  │  │        Domain            │     │    │
          │  │  │   (Business Logic)       │     │    │
          │  │  │   NO external deps       │     │    │
          │  │  └──────────────────────────┘     │    │
          │  │                                    │    │
          │  │  Input Ports ←── Use Cases         │    │
          │  │  Output Ports ──→ (interfaces)     │    │
          │  └──────────────────────────────────┘     │
          │                                            │
          │  Input Adapters      Output Adapters        │
          │  (REST, gRPC,        (DB, Kafka,            │
          │   Kafka consumer)     External APIs)        │
          └──────────────────────────────────────────┘
```

### Key Terms

| Term | Definition | Example |
|------|-----------|---------|
| **Domain** | Pure business logic, no framework dependencies | `Order`, `Money`, `OrderStatus` |
| **Input Port** | Interface that the application exposes | `CreateOrderUseCase` |
| **Output Port** | Interface that the application needs | `OrderRepository`, `PaymentGateway` |
| **Input Adapter** | Drives the application (implements input) | REST Controller, Kafka Consumer |
| **Output Adapter** | Implements external integrations | R2DBC Repository, HTTP Client |
| **Use Case** | Application service implementing input port | `CreateOrderService` |

---

## Package Structure

```
src/main/java/com/example/order/
├── application/                    # Use Cases, Application Services
│   ├── port/
│   │   ├── in/                     # Input Ports (interfaces)
│   │   │   ├── CreateOrderUseCase.java
│   │   │   ├── GetOrderUseCase.java
│   │   │   ├── CancelOrderUseCase.java
│   │   │   └── dto/               # Command/Query DTOs for ports
│   │   │       ├── CreateOrderCommand.java
│   │   │       ├── OrderResponse.java
│   │   │       └── OrderQuery.java
│   │   └── out/                    # Output Ports (interfaces)
│   │       ├── OrderPersistencePort.java
│   │       ├── PaymentPort.java
│   │       ├── NotificationPort.java
│   │       └── OrderEventPublisherPort.java
│   └── service/                    # Use Case implementations
│       ├── CreateOrderService.java
│       ├── GetOrderService.java
│       └── CancelOrderService.java
│
├── domain/                         # Pure domain (NO framework dependencies)
│   ├── model/                      # Entities, Value Objects, Aggregates
│   │   ├── Order.java              # Aggregate Root
│   │   ├── OrderItem.java          # Entity
│   │   ├── Money.java              # Value Object
│   │   ├── OrderId.java            # Value Object (typed ID)
│   │   ├── OrderStatus.java        # Enum
│   │   └── Address.java            # Value Object
│   ├── event/                      # Domain Events
│   │   ├── OrderCreatedEvent.java
│   │   ├── OrderCancelledEvent.java
│   │   └── DomainEvent.java        # Base interface
│   └── exception/                  # Domain Exceptions
│       ├── OrderNotFoundException.java
│       ├── InvalidOrderException.java
│       └── InsufficientStockException.java
│
└── infrastructure/                 # Framework-dependent adapters
    ├── adapter/
    │   ├── in/                     # Input Adapters (driving)
    │   │   ├── rest/
    │   │   │   ├── OrderController.java
    │   │   │   ├── OrderRequestDto.java
    │   │   │   ├── OrderResponseDto.java
    │   │   │   └── OrderRestMapper.java
    │   │   ├── grpc/
    │   │   │   └── OrderGrpcService.java
    │   │   └── messaging/
    │   │       └── OrderEventKafkaConsumer.java
    │   └── out/                    # Output Adapters (driven)
    │       ├── persistence/
    │       │   ├── OrderR2dbcRepository.java
    │       │   ├── OrderEntity.java
    │       │   ├── OrderPersistenceAdapter.java
    │       │   └── OrderPersistenceMapper.java
    │       ├── messaging/
    │       │   └── OrderKafkaPublisher.java
    │       └── external/
    │           ├── PaymentApiAdapter.java
    │           └── NotificationAdapter.java
    └── config/                     # Spring configuration
        ├── BeanConfig.java
        ├── WebFluxConfig.java
        └── KafkaConfig.java
```

---

## Dependency Rules

The most critical principle: **dependencies point inward.**

```
infrastructure → application → domain
     ↓                ↓            ↓
  ALL deps      domain only    NO deps
```

| Layer | Can Depend On | Cannot Depend On |
|-------|--------------|------------------|
| **Domain** | Java standard library ONLY | Spring, JPA, R2DBC, Jackson, anything external |
| **Application** | Domain | Infrastructure, Spring (except minimal annotations) |
| **Infrastructure** | Application, Domain | — (can use everything) |

### Enforcing with ArchUnit

```java
@AnalyzeClasses(packages = "com.example.order")
class ArchitectureTest {

    @ArchTest
    static final ArchRule domain_should_not_depend_on_spring =
        noClasses().that().resideInAPackage("..domain..")
            .should().dependOnClassesThat()
            .resideInAnyPackage(
                "org.springframework..",
                "jakarta.persistence..",
                "io.r2dbc..",
                "com.fasterxml.jackson.."
            )
            .as("Domain must not depend on frameworks");

    @ArchTest
    static final ArchRule domain_should_not_depend_on_application =
        noClasses().that().resideInAPackage("..domain..")
            .should().dependOnClassesThat()
            .resideInAPackage("..application..");

    @ArchTest
    static final ArchRule application_should_not_depend_on_infrastructure =
        noClasses().that().resideInAPackage("..application..")
            .should().dependOnClassesThat()
            .resideInAPackage("..infrastructure..");

    @ArchTest
    static final ArchRule adapters_should_not_depend_on_each_other =
        slices().matching("..adapter.(*)..")
            .should().notDependOnEachOther();
}
```

---

## Domain Layer

### Aggregate Root

```java
/**
 * Order Aggregate Root.
 * ALL business rules live here. No framework annotations.
 * State changes produce domain events.
 */
public class Order {

    private final OrderId id;
    private final CustomerId customerId;
    private final List<OrderItem> items;
    private final Address shippingAddress;
    private OrderStatus status;
    private Money totalAmount;
    private Instant createdAt;
    private Instant updatedAt;

    private final List<DomainEvent> domainEvents = new ArrayList<>();

    // === Factory method (replaces public constructor) ===

    public static Order create(CustomerId customerId, List<OrderItem> items,
                               Address shippingAddress) {
        if (items == null || items.isEmpty()) {
            throw new InvalidOrderException("Order must have at least one item");
        }

        Order order = new Order(
            OrderId.generate(),
            customerId,
            List.copyOf(items),
            shippingAddress,
            OrderStatus.CREATED,
            calculateTotal(items),
            Instant.now(),
            Instant.now()
        );

        order.registerEvent(new OrderCreatedEvent(
            order.id, order.customerId, order.totalAmount, order.createdAt));

        return order;
    }

    private Order(OrderId id, CustomerId customerId, List<OrderItem> items,
                  Address shippingAddress, OrderStatus status, Money totalAmount,
                  Instant createdAt, Instant updatedAt) {
        this.id = Objects.requireNonNull(id);
        this.customerId = Objects.requireNonNull(customerId);
        this.items = items;
        this.shippingAddress = Objects.requireNonNull(shippingAddress);
        this.status = status;
        this.totalAmount = totalAmount;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
    }

    // === Business methods (state transitions with rules) ===

    public void confirm() {
        if (status != OrderStatus.CREATED) {
            throw new InvalidOrderException(
                "Cannot confirm order in status: " + status);
        }
        this.status = OrderStatus.CONFIRMED;
        this.updatedAt = Instant.now();
        registerEvent(new OrderConfirmedEvent(id, totalAmount));
    }

    public void cancel(String reason) {
        if (status == OrderStatus.SHIPPED || status == OrderStatus.DELIVERED) {
            throw new InvalidOrderException(
                "Cannot cancel order in status: " + status);
        }
        this.status = OrderStatus.CANCELLED;
        this.updatedAt = Instant.now();
        registerEvent(new OrderCancelledEvent(id, reason));
    }

    public void ship(String trackingNumber) {
        if (status != OrderStatus.CONFIRMED) {
            throw new InvalidOrderException(
                "Cannot ship order in status: " + status);
        }
        this.status = OrderStatus.SHIPPED;
        this.updatedAt = Instant.now();
        registerEvent(new OrderShippedEvent(id, trackingNumber));
    }

    // === Domain logic ===

    private static Money calculateTotal(List<OrderItem> items) {
        return items.stream()
            .map(OrderItem::subtotal)
            .reduce(Money.ZERO, Money::add);
    }

    // === Domain events ===

    private void registerEvent(DomainEvent event) {
        domainEvents.add(event);
    }

    public List<DomainEvent> getDomainEvents() {
        return List.copyOf(domainEvents);
    }

    public void clearDomainEvents() {
        domainEvents.clear();
    }

    // === Getters (no setters — state changes through business methods only) ===

    public OrderId getId() { return id; }
    public CustomerId getCustomerId() { return customerId; }
    public List<OrderItem> getItems() { return List.copyOf(items); }
    public OrderStatus getStatus() { return status; }
    public Money getTotalAmount() { return totalAmount; }
    public Address getShippingAddress() { return shippingAddress; }
    public Instant getCreatedAt() { return createdAt; }
}
```

### Value Objects

```java
/**
 * Value Object: immutable, equality by value, self-validating.
 */
public record Money(BigDecimal amount, String currency) {

    public static final Money ZERO = new Money(BigDecimal.ZERO, "USD");

    public Money {
        Objects.requireNonNull(amount, "amount must not be null");
        Objects.requireNonNull(currency, "currency must not be null");
        if (amount.scale() > 2) {
            throw new IllegalArgumentException("Amount scale must be <= 2");
        }
    }

    public Money add(Money other) {
        requireSameCurrency(other);
        return new Money(amount.add(other.amount), currency);
    }

    public Money multiply(int quantity) {
        return new Money(amount.multiply(BigDecimal.valueOf(quantity)), currency);
    }

    public boolean isGreaterThan(Money other) {
        requireSameCurrency(other);
        return amount.compareTo(other.amount) > 0;
    }

    private void requireSameCurrency(Money other) {
        if (!currency.equals(other.currency)) {
            throw new IllegalArgumentException(
                "Cannot operate on different currencies: " + currency + " vs " + other.currency);
        }
    }
}

/**
 * Typed ID — prevents mixing up String IDs across entities.
 */
public record OrderId(String value) {

    public OrderId {
        Objects.requireNonNull(value, "OrderId must not be null");
        if (value.isBlank()) {
            throw new IllegalArgumentException("OrderId must not be blank");
        }
    }

    public static OrderId generate() {
        return new OrderId(UUID.randomUUID().toString());
    }

    public static OrderId of(String value) {
        return new OrderId(value);
    }

    @Override
    public String toString() {
        return value;
    }
}
```

### Domain Events

```java
/**
 * Marker interface for domain events. No framework dependencies.
 */
public interface DomainEvent {
    Instant occurredAt();
}

public record OrderCreatedEvent(
    OrderId orderId,
    CustomerId customerId,
    Money totalAmount,
    Instant occurredAt
) implements DomainEvent {}

public record OrderCancelledEvent(
    OrderId orderId,
    String reason,
    Instant occurredAt
) implements DomainEvent {
    public OrderCancelledEvent(OrderId orderId, String reason) {
        this(orderId, reason, Instant.now());
    }
}
```

### Domain Exceptions

```java
/**
 * Domain exceptions — no framework dependencies.
 */
public class OrderNotFoundException extends RuntimeException {
    private final OrderId orderId;

    public OrderNotFoundException(OrderId orderId) {
        super("Order not found: " + orderId);
        this.orderId = orderId;
    }

    public OrderId getOrderId() { return orderId; }
}

public class InvalidOrderException extends RuntimeException {
    public InvalidOrderException(String message) {
        super(message);
    }
}
```

---

## Application Layer

### Input Ports (Use Case Interfaces)

```java
/**
 * Input Port: defines WHAT the application can do.
 * Named after the use case, not technical action.
 */
public interface CreateOrderUseCase {
    Mono<OrderResponse> createOrder(CreateOrderCommand command);
}

public interface GetOrderUseCase {
    Mono<OrderResponse> getOrder(String orderId);
    Flux<OrderResponse> getOrdersByCustomer(String customerId);
}

public interface CancelOrderUseCase {
    Mono<OrderResponse> cancelOrder(CancelOrderCommand command);
}
```

### Command/Query DTOs (Application Layer)

```java
/**
 * Commands: requests to change state. Immutable records.
 */
public record CreateOrderCommand(
    String customerId,
    List<OrderItemCommand> items,
    AddressCommand shippingAddress
) {
    public CreateOrderCommand {
        Objects.requireNonNull(customerId);
        Objects.requireNonNull(items);
        if (items.isEmpty()) {
            throw new IllegalArgumentException("At least one item required");
        }
    }
}

public record OrderItemCommand(String productId, int quantity, BigDecimal price) {}

public record AddressCommand(String street, String city, String zipCode, String country) {}

public record CancelOrderCommand(String orderId, String reason) {}

/**
 * Response DTO: what the application returns.
 */
public record OrderResponse(
    String orderId,
    String customerId,
    String status,
    BigDecimal totalAmount,
    String currency,
    List<OrderItemResponse> items,
    Instant createdAt
) {}
```

### Output Ports (Driven Interfaces)

```java
/**
 * Output Port: defines WHAT the application needs from the outside world.
 * Implementation provided by infrastructure adapters.
 */
public interface OrderPersistencePort {
    Mono<Order> save(Order order);
    Mono<Order> findById(OrderId id);
    Flux<Order> findByCustomerId(CustomerId customerId);
    Mono<Void> delete(OrderId id);
}

public interface PaymentPort {
    Mono<PaymentResult> processPayment(OrderId orderId, Money amount, CustomerId customerId);
}

public interface OrderEventPublisherPort {
    Mono<Void> publishEvents(List<DomainEvent> events);
}

public interface NotificationPort {
    Mono<Void> sendOrderConfirmation(OrderId orderId, CustomerId customerId);
}
```

### Use Case Implementation (Application Service)

```java
/**
 * Use Case implementation. Orchestrates domain objects and output ports.
 * This is where the application workflow lives.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class CreateOrderService implements CreateOrderUseCase {

    private final OrderPersistencePort orderPersistence;
    private final PaymentPort paymentPort;
    private final OrderEventPublisherPort eventPublisher;
    private final NotificationPort notificationPort;

    @Override
    public Mono<OrderResponse> createOrder(CreateOrderCommand command) {
        // 1. Map command to domain objects
        CustomerId customerId = CustomerId.of(command.customerId());
        List<OrderItem> items = command.items().stream()
            .map(i -> new OrderItem(
                ProductId.of(i.productId()),
                i.quantity(),
                new Money(i.price(), "USD")))
            .toList();
        Address address = new Address(
            command.shippingAddress().street(),
            command.shippingAddress().city(),
            command.shippingAddress().zipCode(),
            command.shippingAddress().country());

        // 2. Create domain object (business rules enforced inside)
        Order order = Order.create(customerId, items, address);

        // 3. Orchestrate: persist → payment → publish events → notify
        return orderPersistence.save(order)
            .flatMap(saved -> paymentPort
                .processPayment(saved.getId(), saved.getTotalAmount(), customerId)
                .flatMap(paymentResult -> {
                    if (paymentResult.isSuccessful()) {
                        saved.confirm();
                        return orderPersistence.save(saved);
                    }
                    saved.cancel("Payment failed: " + paymentResult.failureReason());
                    return orderPersistence.save(saved);
                }))
            .flatMap(finalOrder -> {
                // Publish domain events
                List<DomainEvent> events = finalOrder.getDomainEvents();
                finalOrder.clearDomainEvents();
                return eventPublisher.publishEvents(events)
                    .thenReturn(finalOrder);
            })
            .doOnSuccess(o -> {
                if (o.getStatus() == OrderStatus.CONFIRMED) {
                    notificationPort.sendOrderConfirmation(o.getId(), o.getCustomerId())
                        .subscribe(); // fire and forget
                }
            })
            .map(this::toResponse);
    }

    private OrderResponse toResponse(Order order) {
        return new OrderResponse(
            order.getId().value(),
            order.getCustomerId().value(),
            order.getStatus().name(),
            order.getTotalAmount().amount(),
            order.getTotalAmount().currency(),
            order.getItems().stream()
                .map(i -> new OrderItemResponse(
                    i.productId().value(), i.quantity(),
                    i.price().amount()))
                .toList(),
            order.getCreatedAt()
        );
    }
}
```

---

## Infrastructure Layer

### Input Adapter — REST Controller

```java
/**
 * Input Adapter: translates HTTP to use case calls.
 * Depends on Input Port (use case interface), NOT on the service directly.
 */
@RestController
@RequestMapping("/api/orders")
@RequiredArgsConstructor
@Validated
public class OrderController {

    private final CreateOrderUseCase createOrderUseCase;
    private final GetOrderUseCase getOrderUseCase;
    private final CancelOrderUseCase cancelOrderUseCase;
    private final OrderRestMapper mapper;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<OrderResponseDto> createOrder(
            @Valid @RequestBody CreateOrderRequestDto request) {
        CreateOrderCommand command = mapper.toCommand(request);
        return createOrderUseCase.createOrder(command)
            .map(mapper::toResponseDto);
    }

    @GetMapping("/{orderId}")
    public Mono<OrderResponseDto> getOrder(@PathVariable String orderId) {
        return getOrderUseCase.getOrder(orderId)
            .map(mapper::toResponseDto);
    }

    @PostMapping("/{orderId}/cancel")
    public Mono<OrderResponseDto> cancelOrder(
            @PathVariable String orderId,
            @Valid @RequestBody CancelOrderRequestDto request) {
        return cancelOrderUseCase.cancelOrder(
                new CancelOrderCommand(orderId, request.reason()))
            .map(mapper::toResponseDto);
    }
}
```

### Input Adapter — Kafka Consumer

```java
/**
 * Input Adapter: Kafka messages drive use cases.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class OrderEventKafkaConsumer {

    private final CancelOrderUseCase cancelOrderUseCase;

    @KafkaListener(topics = "payment-failures", groupId = "order-service")
    public void handlePaymentFailure(PaymentFailedEvent event) {
        log.info("Payment failed for order {}, cancelling", event.orderId());
        cancelOrderUseCase.cancelOrder(
                new CancelOrderCommand(event.orderId(), "Payment failed"))
            .subscribe();
    }
}
```

### Output Adapter — Persistence (R2DBC)

```java
/**
 * Output Adapter: implements OrderPersistencePort using R2DBC.
 * Handles mapping between domain Order and persistence OrderEntity.
 */
@Component
@RequiredArgsConstructor
public class OrderPersistenceAdapter implements OrderPersistencePort {

    private final OrderR2dbcRepository repository;
    private final OrderPersistenceMapper mapper;

    @Override
    public Mono<Order> save(Order order) {
        OrderEntity entity = mapper.toEntity(order);
        return repository.save(entity)
            .map(mapper::toDomain);
    }

    @Override
    public Mono<Order> findById(OrderId id) {
        return repository.findById(id.value())
            .map(mapper::toDomain);
    }

    @Override
    public Flux<Order> findByCustomerId(CustomerId customerId) {
        return repository.findByCustomerId(customerId.value())
            .map(mapper::toDomain);
    }

    @Override
    public Mono<Void> delete(OrderId id) {
        return repository.deleteById(id.value());
    }
}

/**
 * R2DBC Entity — infrastructure concern, has Spring annotations.
 */
@Table("orders")
public class OrderEntity {
    @Id
    private String id;
    private String customerId;
    private String status;
    private BigDecimal totalAmount;
    private String currency;
    private String shippingStreet;
    private String shippingCity;
    private String shippingZipCode;
    private String shippingCountry;
    private Instant createdAt;
    private Instant updatedAt;
    // getters, setters, all-args constructor
}

public interface OrderR2dbcRepository extends ReactiveCrudRepository<OrderEntity, String> {
    Flux<OrderEntity> findByCustomerId(String customerId);
    Flux<OrderEntity> findByStatus(String status);
}
```

### Output Adapter — External Payment API

```java
/**
 * Output Adapter: implements PaymentPort using WebClient.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class PaymentApiAdapter implements PaymentPort {

    private final WebClient paymentWebClient;

    @Override
    public Mono<PaymentResult> processPayment(OrderId orderId, Money amount,
                                               CustomerId customerId) {
        PaymentRequest request = new PaymentRequest(
            orderId.value(),
            customerId.value(),
            amount.amount(),
            amount.currency()
        );

        return paymentWebClient.post()
            .uri("/api/payments")
            .bodyValue(request)
            .retrieve()
            .bodyToMono(PaymentApiResponse.class)
            .map(response -> new PaymentResult(
                response.isSuccess(),
                response.transactionId(),
                response.failureReason()))
            .onErrorResume(WebClientResponseException.class, e -> {
                log.error("Payment API error: {}", e.getStatusCode(), e);
                return Mono.just(PaymentResult.failed("Payment API error: " + e.getMessage()));
            })
            .timeout(Duration.ofSeconds(10))
            .onErrorResume(TimeoutException.class, e ->
                Mono.just(PaymentResult.failed("Payment API timeout")));
    }
}
```

### Output Adapter — Kafka Event Publisher

```java
/**
 * Output Adapter: publishes domain events to Kafka.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class OrderKafkaPublisher implements OrderEventPublisherPort {

    private final KafkaTemplate<String, Object> kafkaTemplate;

    @Override
    public Mono<Void> publishEvents(List<DomainEvent> events) {
        return Flux.fromIterable(events)
            .flatMap(this::publishEvent)
            .then();
    }

    private Mono<Void> publishEvent(DomainEvent event) {
        String topic = resolveTopic(event);
        String key = resolveKey(event);

        return Mono.fromFuture(kafkaTemplate.send(topic, key, event))
            .doOnSuccess(result -> log.debug("Published {} to {}",
                event.getClass().getSimpleName(), topic))
            .doOnError(e -> log.error("Failed to publish {}", event, e))
            .then();
    }

    private String resolveTopic(DomainEvent event) {
        return switch (event) {
            case OrderCreatedEvent e -> "order.created";
            case OrderConfirmedEvent e -> "order.confirmed";
            case OrderCancelledEvent e -> "order.cancelled";
            case OrderShippedEvent e -> "order.shipped";
            default -> "order.events";
        };
    }

    private String resolveKey(DomainEvent event) {
        return switch (event) {
            case OrderCreatedEvent e -> e.orderId().value();
            case OrderConfirmedEvent e -> e.orderId().value();
            case OrderCancelledEvent e -> e.orderId().value();
            case OrderShippedEvent e -> e.orderId().value();
            default -> UUID.randomUUID().toString();
        };
    }
}
```

### Spring Configuration (Wiring)

```java
/**
 * Bean configuration: wires adapters to ports.
 * This is the ONLY place where the full dependency graph is assembled.
 */
@Configuration
public class BeanConfig {

    /**
     * If using constructor injection with @Component/@Service on all classes,
     * Spring auto-wires everything. This config is needed only for explicit wiring
     * or when adapters don't have @Component.
     */

    @Bean
    public WebClient paymentWebClient() {
        return WebClient.builder()
            .baseUrl("http://payment-service:8080")
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .build();
    }
}
```

---

## Mapping Strategy

Three distinct models exist at each boundary:

```
REST DTO ←→ Domain Model ←→ Persistence Entity
  (API)      (Business)        (Database)
```

### Why Separate Models?

| Model | Purpose | Changes When |
|-------|---------|-------------|
| REST DTO | API contract, validation annotations | API version changes |
| Domain Model | Business rules, behavior | Business requirements change |
| Persistence Entity | DB schema mapping, R2DBC annotations | Schema/DB changes |

### MapStruct Mapper — REST Layer

```java
@Mapper(componentModel = "spring")
public interface OrderRestMapper {

    @Mapping(target = "items", source = "items")
    @Mapping(target = "shippingAddress", source = "address")
    CreateOrderCommand toCommand(CreateOrderRequestDto request);

    @Mapping(target = "orderId", source = "orderId")
    @Mapping(target = "status", source = "status")
    @Mapping(target = "total", source = "totalAmount")
    OrderResponseDto toResponseDto(OrderResponse response);

    OrderItemCommand toItemCommand(OrderItemRequestDto dto);
    AddressCommand toAddressCommand(AddressRequestDto dto);
}
```

### MapStruct Mapper — Persistence Layer

```java
@Mapper(componentModel = "spring")
public interface OrderPersistenceMapper {

    default OrderEntity toEntity(Order order) {
        OrderEntity entity = new OrderEntity();
        entity.setId(order.getId().value());
        entity.setCustomerId(order.getCustomerId().value());
        entity.setStatus(order.getStatus().name());
        entity.setTotalAmount(order.getTotalAmount().amount());
        entity.setCurrency(order.getTotalAmount().currency());
        entity.setShippingStreet(order.getShippingAddress().street());
        entity.setShippingCity(order.getShippingAddress().city());
        entity.setShippingZipCode(order.getShippingAddress().zipCode());
        entity.setShippingCountry(order.getShippingAddress().country());
        entity.setCreatedAt(order.getCreatedAt());
        entity.setUpdatedAt(Instant.now());
        return entity;
    }

    default Order toDomain(OrderEntity entity) {
        return Order.reconstitute(
            OrderId.of(entity.getId()),
            CustomerId.of(entity.getCustomerId()),
            List.of(), // items loaded separately or via join
            new Address(entity.getShippingStreet(), entity.getShippingCity(),
                entity.getShippingZipCode(), entity.getShippingCountry()),
            OrderStatus.valueOf(entity.getStatus()),
            new Money(entity.getTotalAmount(), entity.getCurrency()),
            entity.getCreatedAt(),
            entity.getUpdatedAt()
        );
    }
}
```

> **Tip:** For reconstitution from DB, add a `Order.reconstitute(...)` factory method that bypasses business validation (data is already valid — it was validated when created).

```java
// In Order.java — reconstitution factory
public static Order reconstitute(OrderId id, CustomerId customerId,
        List<OrderItem> items, Address shippingAddress, OrderStatus status,
        Money totalAmount, Instant createdAt, Instant updatedAt) {
    return new Order(id, customerId, items, shippingAddress,
        status, totalAmount, createdAt, updatedAt);
    // No events registered — this is loading, not a new action
}
```

---

## Testing Strategy

### Layer-by-Layer Approach

| Layer | Test Type | What to Mock | What to Assert |
|-------|-----------|-------------|----------------|
| **Domain** | Unit tests | Nothing — pure logic | Business rules, state transitions, events |
| **Application** | Unit tests | Output ports (mocked) | Use case orchestration, port interactions |
| **Infrastructure** | Integration tests | Nothing (real DB/Kafka) | Adapters work with real systems |
| **E2E** | Full integration | External services (WireMock) | Full flow through all layers |

### Domain Unit Tests

```java
class OrderTest {

    @Test
    void shouldCreateOrderWithCorrectTotal() {
        // Given
        List<OrderItem> items = List.of(
            new OrderItem(ProductId.of("P1"), 2, new Money(BigDecimal.TEN, "USD")),
            new OrderItem(ProductId.of("P2"), 1, new Money(BigDecimal.valueOf(25), "USD"))
        );

        // When
        Order order = Order.create(
            CustomerId.of("C1"), items,
            new Address("123 St", "NYC", "10001", "US"));

        // Then
        assertThat(order.getStatus()).isEqualTo(OrderStatus.CREATED);
        assertThat(order.getTotalAmount())
            .isEqualTo(new Money(BigDecimal.valueOf(45), "USD"));
        assertThat(order.getDomainEvents()).hasSize(1);
        assertThat(order.getDomainEvents().get(0))
            .isInstanceOf(OrderCreatedEvent.class);
    }

    @Test
    void shouldRejectEmptyOrder() {
        assertThatThrownBy(() -> Order.create(
            CustomerId.of("C1"), List.of(),
            new Address("123 St", "NYC", "10001", "US")))
            .isInstanceOf(InvalidOrderException.class)
            .hasMessageContaining("at least one item");
    }

    @Test
    void shouldTransitionFromCreatedToConfirmed() {
        Order order = createTestOrder();
        order.confirm();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.CONFIRMED);
    }

    @Test
    void shouldNotAllowCancellingShippedOrder() {
        Order order = createTestOrder();
        order.confirm();
        order.ship("TRACK-123");

        assertThatThrownBy(() -> order.cancel("Changed mind"))
            .isInstanceOf(InvalidOrderException.class);
    }
}
```

### Application Layer Tests (Mocked Ports)

```java
@ExtendWith(MockitoExtension.class)
class CreateOrderServiceTest {

    @Mock
    private OrderPersistencePort orderPersistence;
    @Mock
    private PaymentPort paymentPort;
    @Mock
    private OrderEventPublisherPort eventPublisher;
    @Mock
    private NotificationPort notificationPort;

    @InjectMocks
    private CreateOrderService service;

    @Test
    void shouldCreateAndConfirmOrderOnSuccessfulPayment() {
        // Given
        CreateOrderCommand command = new CreateOrderCommand(
            "customer-1",
            List.of(new OrderItemCommand("product-1", 2, BigDecimal.TEN)),
            new AddressCommand("123 St", "NYC", "10001", "US")
        );

        when(orderPersistence.save(any(Order.class)))
            .thenAnswer(inv -> Mono.just(inv.getArgument(0)));
        when(paymentPort.processPayment(any(), any(), any()))
            .thenReturn(Mono.just(PaymentResult.success("TX-001")));
        when(eventPublisher.publishEvents(anyList()))
            .thenReturn(Mono.empty());
        when(notificationPort.sendOrderConfirmation(any(), any()))
            .thenReturn(Mono.empty());

        // When
        OrderResponse response = service.createOrder(command).block();

        // Then
        assertThat(response).isNotNull();
        assertThat(response.status()).isEqualTo("CONFIRMED");
        verify(orderPersistence, times(2)).save(any(Order.class));
        verify(paymentPort).processPayment(any(), any(), any());
        verify(eventPublisher).publishEvents(anyList());
    }

    @Test
    void shouldCancelOrderOnPaymentFailure() {
        // Given
        CreateOrderCommand command = createTestCommand();

        when(orderPersistence.save(any(Order.class)))
            .thenAnswer(inv -> Mono.just(inv.getArgument(0)));
        when(paymentPort.processPayment(any(), any(), any()))
            .thenReturn(Mono.just(PaymentResult.failed("Insufficient funds")));
        when(eventPublisher.publishEvents(anyList()))
            .thenReturn(Mono.empty());

        // When
        OrderResponse response = service.createOrder(command).block();

        // Then
        assertThat(response.status()).isEqualTo("CANCELLED");
    }
}
```

### Infrastructure Integration Tests

```java
@SpringBootTest
@Testcontainers
class OrderPersistenceAdapterIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("testdb");

    @DynamicPropertySource
    static void overrideProps(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () -> "r2dbc:postgresql://" +
            postgres.getHost() + ":" + postgres.getMappedPort(5432) + "/testdb");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
    }

    @Autowired
    private OrderPersistenceAdapter adapter;

    @Test
    void shouldSaveAndRetrieveOrder() {
        // Given
        Order order = createTestOrder();

        // When
        Order saved = adapter.save(order).block();
        Order retrieved = adapter.findById(order.getId()).block();

        // Then
        assertThat(retrieved).isNotNull();
        assertThat(retrieved.getId()).isEqualTo(order.getId());
        assertThat(retrieved.getStatus()).isEqualTo(order.getStatus());
        assertThat(retrieved.getTotalAmount()).isEqualTo(order.getTotalAmount());
    }
}
```

---

## CQRS Integration

CQRS (Command Query Responsibility Segregation) fits naturally with hexagonal architecture.

### Separate Command and Query Ports

```java
// === Command side ===

public interface CreateOrderUseCase {
    Mono<OrderId> createOrder(CreateOrderCommand command);
}

public interface CancelOrderUseCase {
    Mono<Void> cancelOrder(CancelOrderCommand command);
}

// Command ports use the write-optimized persistence
public interface OrderCommandPort {
    Mono<Order> save(Order order);
}

// === Query side ===

public interface GetOrderQuery {
    Mono<OrderReadModel> getById(String orderId);
}

public interface SearchOrdersQuery {
    Flux<OrderSummary> search(OrderSearchCriteria criteria);
}

// Query ports use read-optimized stores (denormalized views)
public interface OrderQueryPort {
    Mono<OrderReadModel> findById(String orderId);
    Flux<OrderSummary> search(OrderSearchCriteria criteria);
}
```

### Read Model (Optimized for Queries)

```java
/**
 * Read model — flat, denormalized, query-optimized.
 * NOT a domain object. Lives in application layer.
 */
public record OrderReadModel(
    String orderId,
    String customerName,      // denormalized from Customer
    String customerEmail,     // denormalized from Customer
    String status,
    BigDecimal totalAmount,
    int itemCount,
    String shippingCity,
    Instant createdAt,
    Instant lastUpdatedAt
) {}

public record OrderSummary(
    String orderId,
    String status,
    BigDecimal totalAmount,
    Instant createdAt
) {}
```

### Query Adapter (Read-Optimized)

```java
@Component
@RequiredArgsConstructor
public class OrderQueryAdapter implements OrderQueryPort {

    private final DatabaseClient databaseClient;

    @Override
    public Mono<OrderReadModel> findById(String orderId) {
        return databaseClient.sql("""
                SELECT o.id, o.status, o.total_amount, o.item_count,
                       o.shipping_city, o.created_at, o.updated_at,
                       c.name as customer_name, c.email as customer_email
                FROM orders o
                JOIN customers c ON o.customer_id = c.id
                WHERE o.id = :orderId
                """)
            .bind("orderId", orderId)
            .map(row -> new OrderReadModel(
                row.get("id", String.class),
                row.get("customer_name", String.class),
                row.get("customer_email", String.class),
                row.get("status", String.class),
                row.get("total_amount", BigDecimal.class),
                row.get("item_count", Integer.class),
                row.get("shipping_city", String.class),
                row.get("created_at", Instant.class),
                row.get("updated_at", Instant.class)
            ))
            .one();
    }
}
```

### Package Structure with CQRS

```
application/
├── command/
│   ├── port/in/          # CreateOrderUseCase, CancelOrderUseCase
│   ├── port/out/         # OrderCommandPort, PaymentPort
│   └── service/          # CreateOrderService, CancelOrderService
└── query/
    ├── port/in/          # GetOrderQuery, SearchOrdersQuery
    ├── port/out/         # OrderQueryPort
    └── service/          # OrderQueryService
```

---

## When to Use vs When Overkill

### ✅ Use Hexagonal When

| Scenario | Why |
|----------|-----|
| Complex business logic | Domain layer isolates and protects rules |
| Multiple input channels | REST + gRPC + Kafka + CLI → same use cases |
| Multiple output targets | Swap DB, switch from REST to gRPC, add caching |
| Long-lived project | Architecture scales with complexity |
| Team > 3 developers | Clear boundaries = parallel work |
| Microservices | Each service has clean, testable core |

### ❌ Skip Hexagonal When

| Scenario | Why | Alternative |
|----------|-----|-------------|
| Simple CRUD | No business logic to protect | Standard layered (Controller → Service → Repository) |
| Prototype / PoC | Speed matters more than architecture | Direct Spring Boot |
| < 3 entities | Over-engineering for small scope | Package-by-feature |
| Solo developer, short deadline | Architecture overhead not justified | Clean layered with service layer |
| BFF (Backend For Frontend) | Pure API aggregation, no domain | Simple service layer |

### Pragmatic Middle Ground

Not every service needs full hexagonal. Use **hexagonal-lite**:

```
# Full hexagonal (complex services):
application/port/in/ + port/out/ + service/
domain/model/ + event/ + exception/
infrastructure/adapter/in/ + adapter/out/ + config/

# Hexagonal-lite (medium services):
domain/          # Domain models + business logic
service/         # Application services (implicit ports)
web/             # Controllers (input adapter)
persistence/     # Repositories (output adapter)

# Simple layered (CRUD services):
controller/
service/
repository/
model/
```

---

## Anti-Patterns

### ❌ Leaking Infrastructure into Domain

```java
// ❌ BAD: Domain model has Spring/JPA annotations
@Entity
@Table(name = "orders")
public class Order {
    @Id @GeneratedValue
    private Long id;

    @Column(name = "status")
    private String status;
    // Domain is now coupled to JPA
}

// ✅ GOOD: Domain is pure Java
public class Order {
    private final OrderId id;
    private OrderStatus status;
    // No annotations, no framework deps
}

// Separate persistence entity in infrastructure:
@Table("orders")
public class OrderEntity {
    @Id private String id;
    private String status;
}
```

### ❌ Anemic Domain Model

```java
// ❌ BAD: Domain model is just data — all logic in service
public class Order {
    private String id;
    private String status;
    // Only getters and setters — no behavior
}

// Service does everything:
public class OrderService {
    public void cancelOrder(Order order) {
        if (order.getStatus().equals("SHIPPED")) {
            throw new RuntimeException("Cannot cancel");
        }
        order.setStatus("CANCELLED"); // business rule in service, not domain
    }
}

// ✅ GOOD: Domain model owns its behavior
public class Order {
    public void cancel(String reason) {
        if (status == OrderStatus.SHIPPED || status == OrderStatus.DELIVERED) {
            throw new InvalidOrderException("Cannot cancel in status: " + status);
        }
        this.status = OrderStatus.CANCELLED;
        registerEvent(new OrderCancelledEvent(id, reason));
    }
}
```

### ❌ Use Case Doing Too Much

```java
// ❌ BAD: Use case contains business logic that belongs in domain
public class CreateOrderService implements CreateOrderUseCase {
    public Mono<OrderResponse> createOrder(CreateOrderCommand cmd) {
        // Business validation in application layer — WRONG
        if (cmd.items().stream().anyMatch(i -> i.quantity() <= 0)) {
            throw new ValidationException("Quantity must be positive");
        }
        BigDecimal total = cmd.items().stream()
            .map(i -> i.price().multiply(BigDecimal.valueOf(i.quantity())))
            .reduce(BigDecimal.ZERO, BigDecimal::add);
        // ...
    }
}

// ✅ GOOD: Use case orchestrates, domain validates
public class CreateOrderService implements CreateOrderUseCase {
    public Mono<OrderResponse> createOrder(CreateOrderCommand cmd) {
        Order order = Order.create(customerId, items, address);
        // Domain constructor validates and calculates
        return orderPersistence.save(order).map(this::toResponse);
    }
}
```

### ❌ Adapter Depending on Another Adapter

```java
// ❌ BAD: REST adapter calls persistence adapter directly
@RestController
public class OrderController {
    private final OrderPersistenceAdapter persistence; // bypasses use case!

    @GetMapping("/{id}")
    public Mono<Order> get(@PathVariable String id) {
        return persistence.findById(OrderId.of(id));
    }
}

// ✅ GOOD: All adapters go through ports
@RestController
public class OrderController {
    private final GetOrderUseCase getOrderUseCase; // goes through input port

    @GetMapping("/{id}")
    public Mono<OrderResponseDto> get(@PathVariable String id) {
        return getOrderUseCase.getOrder(id).map(mapper::toDto);
    }
}
```

### ❌ Sharing Domain Models in API Responses

```java
// ❌ BAD: Exposing domain model directly as API response
@GetMapping("/{id}")
public Mono<Order> getOrder(@PathVariable String id) {
    return orderService.findById(id); // Domain object leaked to API
    // Internal fields exposed, serialization issues, coupling
}

// ✅ GOOD: Map to dedicated DTO
@GetMapping("/{id}")
public Mono<OrderResponseDto> getOrder(@PathVariable String id) {
    return getOrderUseCase.getOrder(id)
        .map(mapper::toResponseDto); // Explicit DTO for API contract
}
```

---

## Key Design Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Domain model | Rich (behavior + data) | Encapsulates business rules, prevents anemic model |
| IDs | Typed Value Objects (OrderId, not String) | Type safety, prevents mixing IDs |
| Mapping | Explicit mappers per boundary | Decouples layers, allows independent evolution |
| Events | Domain events in domain layer | Domain owns what happened; infrastructure decides where to publish |
| Validation | Domain validates business rules; DTOs validate format | Each layer validates its own concerns |
| Testing | Unit for domain, mock for application, integration for infra | Fast feedback where it matters most |
| ArchUnit | Enforce dependency rules in CI | Catches architecture violations automatically |