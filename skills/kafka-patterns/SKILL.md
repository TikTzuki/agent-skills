---
name: kafka-patterns
description: >
  Comprehensive Apache Kafka patterns for Java Spring WebFlux applications.
  Covers producer/consumer patterns, exactly-once semantics, reactive Kafka,
  error handling with DLT, Schema Registry, testing, monitoring, and production
  configuration. Use when implementing Kafka messaging in Spring Boot 3.x projects.
version: 1.0.0
---

# Kafka Patterns for Spring WebFlux

Production-ready Kafka patterns for Java 17+ / Spring Boot 3.x applications.

## Quick Reference

| Category | When to Use | Jump To |
|----------|------------|---------|
| Producer — Sync/Async | Sending messages to Kafka | [Producer Patterns](#producer-patterns) |
| Consumer — Manual Commit | Precise offset control | [Consumer Patterns](#consumer-patterns) |
| Exactly-Once | Financial, order processing | [Exactly-Once Semantics](#exactly-once-semantics) |
| Reactive Kafka | WebFlux / non-blocking pipelines | [Reactive Kafka](#reactive-kafka-reactor-kafka) |
| Error Handling & DLT | Retry + dead-letter routing | [Error Handling](#error-handling) |
| Schema Registry | Avro / JSON Schema evolution | [Schema Registry](#schema-registry-integration) |
| Testing | EmbeddedKafka, Testcontainers | [Testing](#testing) |
| Production Config | Tuning for throughput/durability | [Production Configuration](#production-configuration) |
| Anti-Patterns | Common mistakes and fixes | [Anti-Patterns](#common-anti-patterns) |

---

## Dependencies

```xml
<!-- Spring Kafka -->
<dependency>
    <groupId>org.springframework.kafka</groupId>
    <artifactId>spring-kafka</artifactId>
</dependency>

<!-- Reactive Kafka (reactor-kafka) -->
<dependency>
    <groupId>io.projectreactor.kafka</groupId>
    <artifactId>reactor-kafka</artifactId>
</dependency>

<!-- Schema Registry (Confluent) -->
<dependency>
    <groupId>io.confluent</groupId>
    <artifactId>kafka-avro-serializer</artifactId>
    <version>7.6.0</version>
</dependency>

<!-- Testing -->
<dependency>
    <groupId>org.springframework.kafka</groupId>
    <artifactId>spring-kafka-test</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>kafka</artifactId>
    <scope>test</scope>
</dependency>
```

---

## Producer Patterns

### Basic Configuration

```java
@Configuration
public class KafkaProducerConfig {

    @Bean
    public ProducerFactory<String, Object> producerFactory(KafkaProperties properties) {
        Map<String, Object> props = properties.buildProducerProperties(null);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        props.put(ProducerConfig.RETRIES_CONFIG, 3);
        props.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5);
        return new DefaultKafkaProducerFactory<>(props);
    }

    @Bean
    public KafkaTemplate<String, Object> kafkaTemplate(
            ProducerFactory<String, Object> producerFactory) {
        return new KafkaTemplate<>(producerFactory);
    }
}
```

### Async Producer (Default — Non-Blocking)

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderEventProducer {

    private final KafkaTemplate<String, Object> kafkaTemplate;

    /**
     * Fire-and-forget with callback logging.
     * Use when: losing a message is acceptable (metrics, logs).
     */
    public void sendAsync(String topic, String key, Object payload) {
        CompletableFuture<SendResult<String, Object>> future =
            kafkaTemplate.send(topic, key, payload);

        future.whenComplete((result, ex) -> {
            if (ex != null) {
                log.error("Failed to send message key={} to topic={}", key, topic, ex);
            } else {
                RecordMetadata meta = result.getRecordMetadata();
                log.debug("Sent key={} to {}-{} offset={}",
                    key, meta.topic(), meta.partition(), meta.offset());
            }
        });
    }
}
```

### Sync Producer (Blocking — Guaranteed Acknowledgment)

```java
/**
 * Blocks until broker acknowledges. Use for critical messages
 * where you must confirm delivery before proceeding.
 */
public SendResult<String, Object> sendSync(String topic, String key, Object payload) {
    try {
        return kafkaTemplate.send(topic, key, payload)
            .get(10, TimeUnit.SECONDS);
    } catch (ExecutionException e) {
        throw new KafkaPublishException("Broker rejected message", e.getCause());
    } catch (TimeoutException e) {
        throw new KafkaPublishException("Send timed out after 10s", e);
    } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        throw new KafkaPublishException("Send interrupted", e);
    }
}
```

### Producer with Headers and Timestamp

```java
public void sendWithHeaders(String topic, String key, Object payload,
                            Map<String, String> headers) {
    ProducerRecord<String, Object> record = new ProducerRecord<>(topic, key, payload);

    headers.forEach((k, v) ->
        record.headers().add(k, v.getBytes(StandardCharsets.UTF_8)));
    record.headers().add("X-Correlation-Id", UUID.randomUUID().toString()
        .getBytes(StandardCharsets.UTF_8));
    record.headers().add("X-Source-Service", "order-service"
        .getBytes(StandardCharsets.UTF_8));

    kafkaTemplate.send(record);
}
```

### Custom Serializer

```java
public class OrderEventSerializer implements Serializer<OrderEvent> {

    private final ObjectMapper objectMapper = new ObjectMapper()
        .registerModule(new JavaTimeModule())
        .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    @Override
    public byte[] serialize(String topic, OrderEvent data) {
        if (data == null) return null;
        try {
            return objectMapper.writeValueAsBytes(data);
        } catch (JsonProcessingException e) {
            throw new SerializationException("Failed to serialize OrderEvent", e);
        }
    }
}
```

### Transactional Producer

```java
@Configuration
public class KafkaTransactionalConfig {

    @Bean
    public ProducerFactory<String, Object> producerFactory(KafkaProperties properties) {
        Map<String, Object> props = properties.buildProducerProperties(null);
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        props.put(ProducerConfig.ACKS_CONFIG, "all");

        DefaultKafkaProducerFactory<String, Object> factory =
            new DefaultKafkaProducerFactory<>(props);
        factory.setTransactionalIdPrefix("order-tx-");
        return factory;
    }
}

@Service
@RequiredArgsConstructor
public class TransactionalProducer {

    private final KafkaTemplate<String, Object> kafkaTemplate;

    /**
     * All messages in the block are committed atomically.
     * If any send fails, ALL are rolled back.
     */
    public void sendTransactional(Order order) {
        kafkaTemplate.executeInTransaction(ops -> {
            ops.send("orders", order.id(), new OrderCreatedEvent(order));
            ops.send("inventory", order.id(), new ReserveStockCommand(order.items()));
            ops.send("notifications", order.id(), new OrderNotification(order));
            return true;
        });
    }
}
```

---

## Consumer Patterns

### Basic Consumer with Manual Acknowledgment

```java
@Configuration
public class KafkaConsumerConfig {

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, Object>
            kafkaListenerContainerFactory(ConsumerFactory<String, Object> consumerFactory) {

        ConcurrentKafkaListenerContainerFactory<String, Object> factory =
            new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(consumerFactory);
        factory.setConcurrency(3); // 3 consumer threads
        factory.getContainerProperties().setAckMode(ContainerProperties.AckMode.MANUAL_IMMEDIATE);
        return factory;
    }
}
```

```java
@Component
@Slf4j
public class OrderEventConsumer {

    @KafkaListener(
        topics = "orders",
        groupId = "order-processor",
        containerFactory = "kafkaListenerContainerFactory"
    )
    public void consume(
            @Payload OrderEvent event,
            @Header(KafkaHeaders.RECEIVED_KEY) String key,
            @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
            @Header(KafkaHeaders.OFFSET) long offset,
            Acknowledgment ack) {
        try {
            log.info("Processing order event key={} partition={} offset={}", key, partition, offset);
            processOrder(event);
            ack.acknowledge(); // commit offset only after successful processing
        } catch (RetryableException e) {
            // Don't ack — message will be redelivered
            log.warn("Retryable error for key={}, will retry", key, e);
            throw e;
        } catch (Exception e) {
            log.error("Fatal error processing key={}", key, e);
            ack.acknowledge(); // ack to avoid poison pill; route to DLT separately
        }
    }
}
```

### Batch Consumer

```java
@Bean
public ConcurrentKafkaListenerContainerFactory<String, Object>
        batchListenerFactory(ConsumerFactory<String, Object> consumerFactory) {

    ConcurrentKafkaListenerContainerFactory<String, Object> factory =
        new ConcurrentKafkaListenerContainerFactory<>();
    factory.setConsumerFactory(consumerFactory);
    factory.setBatchListener(true);
    factory.setConcurrency(3);
    factory.getContainerProperties().setAckMode(ContainerProperties.AckMode.MANUAL);
    return factory;
}

@KafkaListener(topics = "analytics-events", groupId = "analytics-batch",
               containerFactory = "batchListenerFactory")
public void consumeBatch(List<ConsumerRecord<String, AnalyticsEvent>> records,
                         Acknowledgment ack) {
    log.info("Received batch of {} records", records.size());
    try {
        List<AnalyticsEvent> events = records.stream()
            .map(ConsumerRecord::value)
            .toList();
        analyticsService.processBatch(events);
        ack.acknowledge();
    } catch (Exception e) {
        log.error("Batch processing failed", e);
        // nack — entire batch will be redelivered
    }
}
```

### Consumer Group Strategies

| Strategy | Config | Use Case |
|----------|--------|----------|
| Range | `partition.assignment.strategy=RangeAssignor` | Co-partitioned topics, predictable assignment |
| RoundRobin | `RoundRobinAssignor` | Even distribution across consumers |
| Sticky | `StickyAssignor` | Minimizes partition movement during rebalance |
| CooperativeSticky | `CooperativeStickyAssignor` | **Recommended.** Incremental rebalance, no stop-the-world |

```yaml
spring:
  kafka:
    consumer:
      properties:
        partition.assignment.strategy: org.apache.kafka.clients.consumer.CooperativeStickyAssignor
        group.instance.id: ${HOSTNAME}  # Static membership — avoids unnecessary rebalances
        session.timeout.ms: 45000
        heartbeat.interval.ms: 15000
```

---

## Exactly-Once Semantics

Exactly-once requires coordination across producer, consumer, and broker.

### Configuration

```yaml
spring:
  kafka:
    producer:
      acks: all
      properties:
        enable.idempotence: true
        max.in.flight.requests.per.connection: 5
      transaction-id-prefix: "order-tx-"
    consumer:
      properties:
        isolation.level: read_committed  # only read committed transactional messages
      enable-auto-commit: false
```

### Consume-Transform-Produce Pattern

```java
@Component
@RequiredArgsConstructor
public class ExactlyOnceProcessor {

    private final KafkaTemplate<String, Object> kafkaTemplate;

    @KafkaListener(topics = "raw-orders", groupId = "order-enricher")
    public void processExactlyOnce(ConsumerRecord<String, RawOrder> record,
                                   Acknowledgment ack) {
        kafkaTemplate.executeInTransaction(ops -> {
            // Transform
            EnrichedOrder enriched = enrich(record.value());

            // Produce to output topic within same transaction
            ops.send("enriched-orders", record.key(), enriched);

            // Offset is committed as part of the transaction
            ack.acknowledge();
            return null;
        });
    }
}
```

### Idempotent Consumer (Application-Level Deduplication)

```java
@Service
@RequiredArgsConstructor
public class IdempotentOrderProcessor {

    private final ProcessedEventRepository processedEvents;
    private final OrderService orderService;

    @Transactional
    public void process(String eventId, OrderEvent event) {
        // Check if already processed
        if (processedEvents.existsById(eventId)) {
            log.info("Event {} already processed, skipping", eventId);
            return;
        }

        // Process
        orderService.handle(event);

        // Mark as processed
        processedEvents.save(new ProcessedEvent(eventId, Instant.now()));
    }
}
```

---

## Reactive Kafka (reactor-kafka)

### Reactive Producer

```java
@Configuration
public class ReactiveKafkaProducerConfig {

    @Bean
    public ReactiveKafkaProducerTemplate<String, Object> reactiveKafkaProducer(
            KafkaProperties properties) {
        Map<String, Object> props = properties.buildProducerProperties(null);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);
        return new ReactiveKafkaProducerTemplate<>(SenderOptions.create(props));
    }
}

@Service
@RequiredArgsConstructor
@Slf4j
public class ReactiveOrderProducer {

    private final ReactiveKafkaProducerTemplate<String, Object> producer;

    public Mono<SenderResult<Void>> send(String topic, String key, Object value) {
        return producer.send(topic, key, value)
            .doOnSuccess(r -> log.debug("Sent to {}-{} offset={}",
                r.recordMetadata().topic(),
                r.recordMetadata().partition(),
                r.recordMetadata().offset()))
            .doOnError(e -> log.error("Send failed key={}", key, e));
    }

    /**
     * Send a batch reactively — backpressure aware.
     */
    public Flux<SenderResult<Void>> sendBatch(String topic, List<OrderEvent> events) {
        return Flux.fromIterable(events)
            .flatMap(event -> producer.send(topic, event.orderId(), event), 16)
            .doOnComplete(() -> log.info("Batch of {} sent", events.size()));
    }
}
```

### Reactive Consumer

```java
@Configuration
public class ReactiveKafkaConsumerConfig {

    @Bean
    public ReactiveKafkaConsumerTemplate<String, OrderEvent> reactiveKafkaConsumer(
            KafkaProperties properties) {
        Map<String, Object> props = properties.buildConsumerProperties(null);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, "order-reactive");
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);

        ReceiverOptions<String, OrderEvent> receiverOptions = ReceiverOptions
            .<String, OrderEvent>create(props)
            .subscription(List.of("orders"))
            .commitInterval(Duration.ofSeconds(5))
            .commitBatchSize(100);

        return new ReactiveKafkaConsumerTemplate<>(receiverOptions);
    }
}

@Service
@RequiredArgsConstructor
@Slf4j
public class ReactiveOrderConsumer {

    private final ReactiveKafkaConsumerTemplate<String, OrderEvent> consumer;
    private final OrderService orderService;

    @PostConstruct
    public void startConsuming() {
        consumer.receiveAutoAck()
            .concatMap(record -> {
                log.info("Received key={} partition={} offset={}",
                    record.key(), record.partition(), record.offset());
                return orderService.process(record.value())
                    .onErrorResume(e -> {
                        log.error("Error processing key={}", record.key(), e);
                        return Mono.empty(); // skip failed, or route to DLT
                    });
            })
            .subscribe();
    }
}
```

### Reactive Consumer with Manual Commit

```java
@PostConstruct
public void startConsuming() {
    consumer.receive()
        .concatMap(record ->
            orderService.process(record.value())
                .then(record.receiverOffset().commit())
                .onErrorResume(e -> {
                    log.error("Processing failed for offset={}", record.offset(), e);
                    return Mono.empty();
                })
        )
        .subscribe();
}
```

---

## Error Handling

### DefaultErrorHandler with Backoff Retry

```java
@Bean
public ConcurrentKafkaListenerContainerFactory<String, Object>
        kafkaListenerContainerFactory(ConsumerFactory<String, Object> consumerFactory,
                                     KafkaTemplate<String, Object> kafkaTemplate) {

    // Retry 3 times with exponential backoff, then route to DLT
    DefaultErrorHandler errorHandler = new DefaultErrorHandler(
        new DeadLetterPublishingRecoverer(kafkaTemplate,
            (record, ex) -> new TopicPartition(record.topic() + ".DLT", record.partition())),
        new FixedBackOff(1000L, 3L)  // 1s interval, 3 attempts
    );

    // Don't retry these — send to DLT immediately
    errorHandler.addNotRetryableExceptions(
        DeserializationException.class,
        ValidationException.class,
        NullPointerException.class
    );

    // Retry these
    errorHandler.addRetryableExceptions(
        DatabaseTimeoutException.class,
        SocketTimeoutException.class
    );

    ConcurrentKafkaListenerContainerFactory<String, Object> factory =
        new ConcurrentKafkaListenerContainerFactory<>();
    factory.setConsumerFactory(consumerFactory);
    factory.setCommonErrorHandler(errorHandler);
    return factory;
}
```

### Exponential Backoff

```java
DefaultErrorHandler errorHandler = new DefaultErrorHandler(
    new DeadLetterPublishingRecoverer(kafkaTemplate),
    new ExponentialBackOff(1000L, 2.0)  // 1s, 2s, 4s...
);
// Cap at 30 seconds
((ExponentialBackOff) errorHandler.getBackOffHandler()).setMaxInterval(30_000L);
```

### Dead Letter Topic (DLT) Consumer

```java
@KafkaListener(topics = "orders.DLT", groupId = "dlt-processor")
public void processDlt(
        ConsumerRecord<String, byte[]> record,
        @Header(KafkaHeaders.DLT_EXCEPTION_MESSAGE) String errorMessage,
        @Header(KafkaHeaders.DLT_ORIGINAL_TOPIC) String originalTopic,
        @Header(KafkaHeaders.DLT_ORIGINAL_OFFSET) long originalOffset,
        @Header(KafkaHeaders.DLT_EXCEPTION_FQCN) String exceptionClass) {

    log.error("DLT received: topic={} offset={} error={} exception={}",
        originalTopic, originalOffset, errorMessage, exceptionClass);

    // Store for manual review / alerting
    dltRepository.save(DltRecord.builder()
        .key(record.key())
        .payload(new String(record.value()))
        .originalTopic(originalTopic)
        .errorMessage(errorMessage)
        .exceptionClass(exceptionClass)
        .receivedAt(Instant.now())
        .build());
}
```

### Custom RetryTemplate (Legacy Approach)

```java
@Bean
public ConcurrentKafkaListenerContainerFactory<String, Object>
        retryListenerFactory(ConsumerFactory<String, Object> consumerFactory) {

    RetryTemplate retryTemplate = RetryTemplate.builder()
        .maxAttempts(3)
        .exponentialBackoff(500, 2.0, 5000)
        .retryOn(TransientException.class)
        .build();

    ConcurrentKafkaListenerContainerFactory<String, Object> factory =
        new ConcurrentKafkaListenerContainerFactory<>();
    factory.setConsumerFactory(consumerFactory);
    factory.setRetryTemplate(retryTemplate);
    factory.setRecoveryCallback(context -> {
        ConsumerRecord<?, ?> record = (ConsumerRecord<?, ?>) context.getAttribute("record");
        log.error("Recovery: exhausted retries for key={}", record.key());
        return null;
    });
    return factory;
}
```

> **Note:** `DefaultErrorHandler` is preferred over `RetryTemplate` in Spring Kafka 3.x.

---

## Schema Registry Integration

### Avro Producer

```yaml
spring:
  kafka:
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: io.confluent.kafka.serializers.KafkaAvroSerializer
      properties:
        schema.registry.url: http://schema-registry:8081
        auto.register.schemas: true
        use.latest.version: true
```

### Avro Schema Definition

```json
{
  "type": "record",
  "name": "OrderEvent",
  "namespace": "com.example.events",
  "fields": [
    {"name": "orderId", "type": "string"},
    {"name": "customerId", "type": "string"},
    {"name": "amount", "type": {"type": "bytes", "logicalType": "decimal", "precision": 10, "scale": 2}},
    {"name": "status", "type": {"type": "enum", "name": "OrderStatus", "symbols": ["CREATED", "CONFIRMED", "SHIPPED", "DELIVERED", "CANCELLED"]}},
    {"name": "createdAt", "type": {"type": "long", "logicalType": "timestamp-millis"}},
    {"name": "items", "type": {"type": "array", "items": {
      "type": "record", "name": "OrderItem", "fields": [
        {"name": "productId", "type": "string"},
        {"name": "quantity", "type": "int"},
        {"name": "price", "type": {"type": "bytes", "logicalType": "decimal", "precision": 10, "scale": 2}}
      ]
    }}}
  ]
}
```

### JSON Schema with Schema Registry

```yaml
spring:
  kafka:
    producer:
      value-serializer: io.confluent.kafka.serializers.json.KafkaJsonSchemaSerializer
      properties:
        schema.registry.url: http://schema-registry:8081
        json.fail.invalid.schema: true
    consumer:
      value-deserializer: io.confluent.kafka.serializers.json.KafkaJsonSchemaDeserializer
      properties:
        schema.registry.url: http://schema-registry:8081
        json.value.type: com.example.events.OrderEvent
```

### Schema Compatibility Strategies

| Strategy | Allowed Changes | Use Case |
|----------|----------------|----------|
| BACKWARD | Remove fields, add optional fields | **Default.** New consumer reads old data |
| FORWARD | Add fields, remove optional fields | Old consumer reads new data |
| FULL | Only add/remove optional fields | Both directions |
| NONE | Anything | Development only |

---

## Testing

### EmbeddedKafka

```java
@SpringBootTest
@EmbeddedKafka(
    partitions = 3,
    topics = {"orders", "orders.DLT"},
    brokerProperties = {
        "listeners=PLAINTEXT://localhost:9092",
        "auto.create.topics.enable=true"
    }
)
class OrderProducerIntegrationTest {

    @Autowired
    private KafkaTemplate<String, Object> kafkaTemplate;

    @Autowired
    private EmbeddedKafkaBroker embeddedKafka;

    @Test
    void shouldProduceAndConsumeOrderEvent() throws Exception {
        // Given
        OrderEvent event = new OrderEvent("order-123", "CREATED", Instant.now());

        // When
        kafkaTemplate.send("orders", event.orderId(), event).get(10, TimeUnit.SECONDS);

        // Then — verify with a test consumer
        Map<String, Object> consumerProps = KafkaTestUtils.consumerProps(
            "test-group", "true", embeddedKafka);
        consumerProps.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        ConsumerFactory<String, OrderEvent> cf = new DefaultKafkaConsumerFactory<>(consumerProps);

        Consumer<String, OrderEvent> consumer = cf.createConsumer();
        embeddedKafka.consumeFromAnEmbeddedTopic(consumer, "orders");

        ConsumerRecords<String, OrderEvent> records =
            KafkaTestUtils.getRecords(consumer, Duration.ofSeconds(10));
        assertThat(records.count()).isGreaterThanOrEqualTo(1);
        assertThat(records.iterator().next().key()).isEqualTo("order-123");

        consumer.close();
    }
}
```

### Testcontainers (Recommended for CI)

```java
@SpringBootTest
@Testcontainers
class OrderKafkaIntegrationTest {

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.6.0"));

    @DynamicPropertySource
    static void overrideProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
    }

    @Autowired
    private OrderEventProducer producer;

    @Autowired
    private KafkaTemplate<String, Object> kafkaTemplate;

    @Test
    void shouldHandleOrderCreatedEvent() {
        // Given
        OrderEvent event = new OrderEvent("order-456", "CREATED", Instant.now());

        // When
        producer.sendSync("orders", event.orderId(), event);

        // Then — verify side effects (DB state, downstream calls, etc.)
        await().atMost(Duration.ofSeconds(10))
            .untilAsserted(() -> {
                Order order = orderRepository.findById("order-456").orElseThrow();
                assertThat(order.getStatus()).isEqualTo("CREATED");
            });
    }
}
```

### Testcontainers with Schema Registry

```java
@Testcontainers
class SchemaRegistryIntegrationTest {

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.6.0"));

    @Container
    static GenericContainer<?> schemaRegistry = new GenericContainer<>(
            DockerImageName.parse("confluentinc/cp-schema-registry:7.6.0"))
        .withNetwork(kafka.getNetwork())
        .withExposedPorts(8081)
        .withEnv("SCHEMA_REGISTRY_HOST_NAME", "schema-registry")
        .withEnv("SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS",
            kafka.getBootstrapServers())
        .dependsOn(kafka);

    @DynamicPropertySource
    static void overrideProps(DynamicPropertyRegistry registry) {
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
        registry.add("spring.kafka.properties.schema.registry.url",
            () -> "http://localhost:" + schemaRegistry.getMappedPort(8081));
    }
}
```

---

## Monitoring

### Key Metrics to Track

| Metric | What It Means | Alert Threshold |
|--------|--------------|-----------------|
| `kafka.consumer.records-lag-max` | Max consumer lag across partitions | > 10,000 |
| `kafka.consumer.records-consumed-rate` | Records consumed per second | Sudden drop |
| `kafka.producer.record-send-rate` | Records sent per second | Sudden drop |
| `kafka.producer.record-error-rate` | Failed sends per second | > 0 sustained |
| `kafka.consumer.commit-rate` | Offset commits per second | Near 0 = stuck |
| `kafka.producer.request-latency-avg` | Average broker response time | > 100ms |

### Micrometer Integration

```java
@Configuration
public class KafkaMetricsConfig {

    @Bean
    public MicrometerConsumerListener<String, Object> consumerListener(MeterRegistry registry) {
        return new MicrometerConsumerListener<>(registry);
    }

    @Bean
    public MicrometerProducerListener<String, Object> producerListener(MeterRegistry registry) {
        return new MicrometerProducerListener<>(registry);
    }

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, Object>
            kafkaListenerContainerFactory(
                ConsumerFactory<String, Object> consumerFactory,
                MicrometerConsumerListener<String, Object> consumerListener) {

        ConcurrentKafkaListenerContainerFactory<String, Object> factory =
            new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(consumerFactory);
        factory.getContainerProperties().setMicrometerEnabled(true);
        consumerFactory.addListener(consumerListener);
        return factory;
    }
}
```

### Custom Consumer Lag Monitoring

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class ConsumerLagMonitor {

    private final AdminClient adminClient;
    private final MeterRegistry registry;

    @Scheduled(fixedRate = 30_000)
    public void checkLag() {
        try {
            Map<TopicPartition, OffsetAndMetadata> offsets =
                adminClient.listConsumerGroupOffsets("order-processor")
                    .partitionsToOffsetAndMetadata().get(10, TimeUnit.SECONDS);

            Map<TopicPartition, ListOffsetsResult.ListOffsetsResultInfo> endOffsets =
                adminClient.listOffsets(
                    offsets.keySet().stream().collect(Collectors.toMap(
                        tp -> tp, tp -> OffsetSpec.latest()))
                ).all().get(10, TimeUnit.SECONDS);

            offsets.forEach((tp, offsetAndMetadata) -> {
                long lag = endOffsets.get(tp).offset() - offsetAndMetadata.offset();
                registry.gauge("kafka.consumer.lag",
                    Tags.of("topic", tp.topic(), "partition", String.valueOf(tp.partition())),
                    lag);
                if (lag > 10_000) {
                    log.warn("High consumer lag: topic={} partition={} lag={}",
                        tp.topic(), tp.partition(), lag);
                }
            });
        } catch (Exception e) {
            log.error("Failed to check consumer lag", e);
        }
    }
}
```

---

## Production Configuration

### Producer Configuration

```yaml
spring:
  kafka:
    bootstrap-servers: kafka-1:9092,kafka-2:9092,kafka-3:9092
    producer:
      acks: all                          # Wait for all ISR replicas
      retries: 2147483647               # Max retries (rely on delivery.timeout.ms)
      batch-size: 32768                  # 32KB batch
      buffer-memory: 67108864           # 64MB buffer
      compression-type: lz4             # Best throughput/ratio balance
      properties:
        enable.idempotence: true
        max.in.flight.requests.per.connection: 5
        delivery.timeout.ms: 120000     # 2 minutes total delivery timeout
        linger.ms: 20                   # Wait 20ms to batch
        request.timeout.ms: 30000
```

### Consumer Configuration

```yaml
spring:
  kafka:
    consumer:
      group-id: order-service
      auto-offset-reset: earliest
      enable-auto-commit: false          # Always manual commit
      max-poll-records: 500
      fetch-min-size: 1048576           # 1MB — wait for enough data
      fetch-max-wait: 500               # max 500ms wait
      properties:
        session.timeout.ms: 45000
        heartbeat.interval.ms: 15000
        max.poll.interval.ms: 300000    # 5 minutes max processing time
        partition.assignment.strategy: org.apache.kafka.clients.consumer.CooperativeStickyAssignor
```

### Topic Configuration (AdminClient)

```java
@Configuration
public class KafkaTopicConfig {

    @Bean
    public NewTopic ordersTopic() {
        return TopicBuilder.name("orders")
            .partitions(12)
            .replicas(3)
            .config(TopicConfig.MIN_IN_SYNC_REPLICAS_CONFIG, "2")
            .config(TopicConfig.RETENTION_MS_CONFIG, String.valueOf(Duration.ofDays(7).toMillis()))
            .config(TopicConfig.CLEANUP_POLICY_CONFIG, "delete")
            .config(TopicConfig.MAX_MESSAGE_BYTES_CONFIG, "1048576") // 1MB
            .build();
    }

    @Bean
    public NewTopic ordersDltTopic() {
        return TopicBuilder.name("orders.DLT")
            .partitions(3)
            .replicas(3)
            .config(TopicConfig.RETENTION_MS_CONFIG, String.valueOf(Duration.ofDays(30).toMillis()))
            .build();
    }
}
```

### Tuning Guidelines

| Goal | Key Settings |
|------|-------------|
| **Max throughput** | `linger.ms=50`, `batch.size=65536`, `compression.type=lz4`, `acks=1` |
| **Max durability** | `acks=all`, `min.insync.replicas=2`, `enable.idempotence=true`, `retries=MAX` |
| **Low latency** | `linger.ms=0`, `batch.size=16384`, `acks=1`, `compression.type=none` |
| **Balanced (recommended)** | `acks=all`, `linger.ms=20`, `batch.size=32768`, `compression.type=lz4` |

---

## Common Anti-Patterns

### ❌ Auto-Commit in Production

```java
// ❌ BAD: Messages lost on crash — offset committed before processing completes
spring.kafka.consumer.enable-auto-commit=true

// ✅ GOOD: Manual commit after successful processing
spring.kafka.consumer.enable-auto-commit=false
// + AckMode.MANUAL_IMMEDIATE
```

### ❌ No Dead Letter Topic

```java
// ❌ BAD: Poison pill blocks entire partition forever
@KafkaListener(topics = "orders")
public void consume(OrderEvent event) {
    process(event); // throws → infinite retry
}

// ✅ GOOD: DLT catches un-processable messages
DefaultErrorHandler errorHandler = new DefaultErrorHandler(
    new DeadLetterPublishingRecoverer(kafkaTemplate),
    new FixedBackOff(1000L, 3L));
```

### ❌ Large Messages

```java
// ❌ BAD: Sending 5MB payloads through Kafka
kafkaTemplate.send("orders", largeOrderWithAllAttachments);

// ✅ GOOD: Claim-check pattern — store payload in S3/DB, send reference
kafkaTemplate.send("orders", new OrderRef(orderId, s3Url));
```

### ❌ Too Many Partitions per Topic

```
# ❌ BAD: 1000 partitions "just in case"
# More partitions = more memory, slower rebalance, more open files

# ✅ GOOD: Start with target-throughput / partition-throughput
# If single consumer handles 10K msg/s and target is 100K → 10 partitions
# Easier to add later than to reduce
```

### ❌ Using Kafka as a Database

```java
// ❌ BAD: Querying Kafka by key, seeking to specific offsets for reads
// Kafka is append-only log, not a database

// ✅ GOOD: Consume → materialize into a query-optimized store (DB, Redis, Elasticsearch)
```

### ❌ Not Setting `max.poll.interval.ms`

```java
// ❌ BAD: Default 5 minutes, but processing takes 10 minutes
// Consumer gets kicked from group → rebalance → duplicate processing

// ✅ GOOD: Set based on actual processing time + buffer
spring.kafka.consumer.properties.max.poll.interval.ms=600000
spring.kafka.consumer.max-poll-records=100  // reduce batch size too
```

### ❌ Ignoring Consumer Lag

```
# ❌ BAD: No monitoring — lag grows silently until hours behind

# ✅ GOOD: Monitor with Micrometer + alert on thresholds
# Use kafka.consumer.records-lag-max metric
# Alert when lag > 10K for > 5 minutes
```

---

## Key Design Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Key selection | Business key (orderId, userId) | Ensures ordering per entity |
| Partitions | 6–12 per topic to start | Balance parallelism vs overhead |
| Replication | 3 replicas, min.insync=2 | Survives single broker failure |
| Retention | 7 days default, 30 days for DLT | Enough for replay; DLT needs longer review |
| Serialization | JSON for simplicity, Avro for schema evolution | JSON if <5 services; Avro if schema governance needed |
| Consumer commit | Manual after processing | Prevents data loss |
| Error handling | DefaultErrorHandler + DLT | Retries transient, dead-letters permanent failures |