---
name: redis-patterns
description: >
  Comprehensive Redis patterns for Java Spring WebFlux applications.
  Covers reactive Redis with Lettuce, caching strategies, distributed locking,
  rate limiting, Pub/Sub, Redis Streams, data structure patterns, key design,
  serialization, cluster configuration, and testing. Use when implementing
  Redis in Spring Boot 3.x reactive projects.
version: 1.0.0
---

# Redis Patterns for Spring WebFlux

Production-ready Redis patterns for Java 17+ / Spring Boot 3.x reactive applications.

## Quick Reference

| Category | When to Use | Jump To |
|----------|------------|---------|
| Reactive Redis Setup | Any Redis + WebFlux project | [Setup](#reactive-redis-setup) |
| Caching Patterns | Cache-Aside, Write-Through, Write-Behind | [Caching](#caching-patterns) |
| Distributed Locking | Mutual exclusion across instances | [Locking](#distributed-locking) |
| Rate Limiting | API throttling, abuse prevention | [Rate Limiting](#rate-limiting) |
| Pub/Sub | Real-time messaging, event broadcasting | [Pub/Sub](#pubsub-patterns) |
| Redis Streams | Event sourcing, message queues | [Streams](#redis-streams) |
| Data Structures | Choosing the right structure | [Data Structures](#data-structure-patterns) |
| Key Design | Namespacing, TTL, eviction | [Key Design](#key-design) |
| Serialization | Jackson, Kryo, Protobuf | [Serialization](#serialization) |
| Cluster & Sentinel | High availability setup | [Cluster](#redis-cluster--sentinel) |
| Testing | Embedded Redis, Testcontainers | [Testing](#testing) |
| Anti-Patterns | Common mistakes and fixes | [Anti-Patterns](#common-anti-patterns) |

---

## Dependencies

```xml
<!-- Spring Data Reactive Redis (Lettuce built-in) -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-redis-reactive</artifactId>
</dependency>

<!-- Redisson (distributed locking, advanced features) -->
<dependency>
    <groupId>org.redisson</groupId>
    <artifactId>redisson-spring-boot-starter</artifactId>
    <version>3.27.0</version>
</dependency>

<!-- Testing -->
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>testcontainers</artifactId>
    <scope>test</scope>
</dependency>
```

---

## Reactive Redis Setup

### Configuration

```yaml
spring:
  data:
    redis:
      host: localhost
      port: 6379
      password: ${REDIS_PASSWORD:}
      timeout: 2000ms
      lettuce:
        pool:
          max-active: 16
          max-idle: 8
          min-idle: 4
          max-wait: 2000ms
        shutdown-timeout: 200ms
```

### ReactiveRedisTemplate Configuration

```java
@Configuration
public class RedisConfig {

    @Bean
    public ReactiveRedisTemplate<String, Object> reactiveRedisTemplate(
            ReactiveRedisConnectionFactory connectionFactory) {

        Jackson2JsonRedisSerializer<Object> serializer =
            new Jackson2JsonRedisSerializer<>(objectMapper(), Object.class);

        RedisSerializationContext<String, Object> context =
            RedisSerializationContext.<String, Object>newSerializationContext(
                    new StringRedisSerializer())
                .value(serializer)
                .hashKey(new StringRedisSerializer())
                .hashValue(serializer)
                .build();

        return new ReactiveRedisTemplate<>(connectionFactory, context);
    }

    @Bean
    public ObjectMapper objectMapper() {
        return new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
            .activateDefaultTyping(
                BasicPolymorphicTypeValidator.builder()
                    .allowIfBaseType(Object.class)
                    .build(),
                ObjectMapper.DefaultTyping.NON_FINAL);
    }

    /**
     * Typed template for specific domain objects — avoids Object casting.
     */
    @Bean
    public ReactiveRedisTemplate<String, UserProfile> userProfileRedisTemplate(
            ReactiveRedisConnectionFactory connectionFactory) {

        Jackson2JsonRedisSerializer<UserProfile> serializer =
            new Jackson2JsonRedisSerializer<>(new ObjectMapper()
                .registerModule(new JavaTimeModule()), UserProfile.class);

        RedisSerializationContext<String, UserProfile> context =
            RedisSerializationContext.<String, UserProfile>newSerializationContext(
                    new StringRedisSerializer())
                .value(serializer)
                .build();

        return new ReactiveRedisTemplate<>(connectionFactory, context);
    }
}
```

### Generic Reactive Redis Operations

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class ReactiveRedisService {

    private final ReactiveRedisTemplate<String, Object> redisTemplate;

    // === Basic String Operations ===

    public Mono<Boolean> set(String key, Object value, Duration ttl) {
        return redisTemplate.opsForValue().set(key, value, ttl);
    }

    public <T> Mono<T> get(String key, Class<T> type) {
        return redisTemplate.opsForValue().get(key)
            .cast(type);
    }

    public Mono<Boolean> delete(String key) {
        return redisTemplate.delete(key).map(count -> count > 0);
    }

    public Mono<Boolean> exists(String key) {
        return redisTemplate.hasKey(key);
    }

    public Mono<Boolean> expire(String key, Duration ttl) {
        return redisTemplate.expire(key, ttl);
    }

    // === Atomic Operations ===

    public Mono<Long> increment(String key) {
        return redisTemplate.opsForValue().increment(key);
    }

    public Mono<Long> increment(String key, long delta) {
        return redisTemplate.opsForValue().increment(key, delta);
    }

    // === Hash Operations ===

    public Mono<Boolean> hashSet(String key, String field, Object value) {
        return redisTemplate.opsForHash().put(key, field, value);
    }

    public <T> Mono<T> hashGet(String key, String field, Class<T> type) {
        return redisTemplate.<String, Object>opsForHash().get(key, field)
            .cast(type);
    }

    public Flux<Map.Entry<Object, Object>> hashGetAll(String key) {
        return redisTemplate.opsForHash().entries(key);
    }
}
```

---

## Caching Patterns

### Cache-Aside (Lazy Loading) — Most Common

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class UserCacheService {

    private final ReactiveRedisTemplate<String, Object> redisTemplate;
    private final UserRepository userRepository;
    private static final Duration CACHE_TTL = Duration.ofMinutes(30);

    /**
     * Cache-Aside: Check cache first → miss → load from DB → store in cache.
     * Best for: read-heavy workloads, data that tolerates slight staleness.
     */
    public Mono<UserProfile> getUserById(String userId) {
        String cacheKey = "user:profile:" + userId;

        return redisTemplate.opsForValue().get(cacheKey)
            .cast(UserProfile.class)
            .switchIfEmpty(Mono.defer(() -> {
                log.debug("Cache miss for key={}", cacheKey);
                return userRepository.findById(userId)
                    .flatMap(user -> redisTemplate.opsForValue()
                        .set(cacheKey, user, CACHE_TTL)
                        .thenReturn(user));
            }));
    }

    /**
     * Invalidate on write.
     */
    public Mono<UserProfile> updateUser(String userId, UserProfile updated) {
        return userRepository.save(updated)
            .flatMap(saved -> redisTemplate.delete("user:profile:" + userId)
                .thenReturn(saved));
    }
}
```

### Write-Through

```java
/**
 * Write-Through: Write to cache AND DB simultaneously.
 * Best for: data consistency is critical, reads are frequent.
 */
public Mono<UserProfile> saveUserWriteThrough(UserProfile user) {
    String cacheKey = "user:profile:" + user.id();
    return userRepository.save(user)
        .flatMap(saved -> redisTemplate.opsForValue()
            .set(cacheKey, saved, CACHE_TTL)
            .thenReturn(saved));
}
```

### Write-Behind (Write-Back) — Async DB Write

```java
/**
 * Write-Behind: Write to cache immediately, async flush to DB.
 * Best for: write-heavy workloads, eventual consistency OK.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class WriteBehindCacheService {

    private final ReactiveRedisTemplate<String, Object> redisTemplate;
    private final UserRepository userRepository;
    private final Sinks.Many<UserProfile> writeSink = Sinks.many().multicast().onBackpressureBuffer();

    @PostConstruct
    public void init() {
        // Flush to DB in batches every 5 seconds or every 100 items
        writeSink.asFlux()
            .bufferTimeout(100, Duration.ofSeconds(5))
            .flatMap(batch -> userRepository.saveAll(batch).collectList())
            .doOnError(e -> log.error("Write-behind flush failed", e))
            .retry()
            .subscribe();
    }

    public Mono<UserProfile> saveWriteBehind(UserProfile user) {
        String cacheKey = "user:profile:" + user.id();
        return redisTemplate.opsForValue()
            .set(cacheKey, user, Duration.ofMinutes(30))
            .doOnSuccess(ok -> writeSink.tryEmitNext(user))
            .thenReturn(user);
    }
}
```

### Spring Cache Abstraction (Reactive)

```java
@Configuration
@EnableCaching
public class CacheConfig extends CachingConfigurerSupport {

    @Bean
    public RedisCacheManager cacheManager(RedisConnectionFactory connectionFactory) {
        RedisCacheConfiguration defaultConfig = RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(Duration.ofMinutes(30))
            .serializeKeysWith(
                RedisSerializationContext.SerializationPair.fromSerializer(new StringRedisSerializer()))
            .serializeValuesWith(
                RedisSerializationContext.SerializationPair.fromSerializer(
                    new GenericJackson2JsonRedisSerializer()))
            .disableCachingNullValues();

        Map<String, RedisCacheConfiguration> perCacheConfig = Map.of(
            "users", defaultConfig.entryTtl(Duration.ofHours(1)),
            "products", defaultConfig.entryTtl(Duration.ofMinutes(15)),
            "config", defaultConfig.entryTtl(Duration.ofHours(24))
        );

        return RedisCacheManager.builder(connectionFactory)
            .cacheDefaults(defaultConfig)
            .withInitialCacheConfigurations(perCacheConfig)
            .transactionAware()
            .build();
    }
}
```

> **Note:** `@Cacheable` does NOT natively support `Mono`/`Flux` returns.
> For reactive caching, use manual Cache-Aside with `ReactiveRedisTemplate` (shown above),
> or use the `@ReactiveCacheable` from the `spring-addons` library or custom AOP.

### Reactive Cacheable via Custom Annotation

```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface ReactiveCacheable {
    String cacheName();
    String key();
    long ttlSeconds() default 1800;
}

@Aspect
@Component
@RequiredArgsConstructor
public class ReactiveCacheAspect {

    private final ReactiveRedisTemplate<String, Object> redisTemplate;

    @Around("@annotation(cacheable)")
    public Object around(ProceedingJoinPoint joinPoint, ReactiveCacheable cacheable) {
        String cacheKey = cacheable.cacheName() + ":" + evaluateKey(cacheable.key(), joinPoint);
        Duration ttl = Duration.ofSeconds(cacheable.ttlSeconds());

        return redisTemplate.opsForValue().get(cacheKey)
            .switchIfEmpty(Mono.defer(() -> {
                try {
                    Mono<?> result = (Mono<?>) joinPoint.proceed();
                    return result.flatMap(value ->
                        redisTemplate.opsForValue().set(cacheKey, value, ttl)
                            .thenReturn(value));
                } catch (Throwable e) {
                    return Mono.error(e);
                }
            }));
    }

    private String evaluateKey(String expression, ProceedingJoinPoint joinPoint) {
        // Use SpEL evaluation for key expressions
        MethodSignature sig = (MethodSignature) joinPoint.getSignature();
        String[] paramNames = sig.getParameterNames();
        Object[] args = joinPoint.getArgs();
        StandardEvaluationContext context = new StandardEvaluationContext();
        for (int i = 0; i < paramNames.length; i++) {
            context.setVariable(paramNames[i], args[i]);
        }
        return new SpelExpressionParser().parseExpression(expression).getValue(context, String.class);
    }
}

// Usage:
@ReactiveCacheable(cacheName = "users", key = "#userId", ttlSeconds = 3600)
public Mono<UserProfile> findById(String userId) {
    return userRepository.findById(userId);
}
```

---

## Distributed Locking

### RedisTemplate-Based Lock (Simple)

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class RedisDistributedLock {

    private final ReactiveRedisTemplate<String, Object> redisTemplate;

    /**
     * Acquire a distributed lock with TTL (auto-release on expiry).
     * Uses SET NX EX (atomic).
     */
    public Mono<Boolean> tryLock(String lockKey, String lockValue, Duration ttl) {
        return redisTemplate.opsForValue()
            .setIfAbsent(lockKey, lockValue, ttl);
    }

    /**
     * Release lock only if we own it (Lua script for atomicity).
     */
    public Mono<Boolean> unlock(String lockKey, String lockValue) {
        String luaScript = """
            if redis.call('get', KEYS[1]) == ARGV[1] then
                return redis.call('del', KEYS[1])
            else
                return 0
            end
            """;
        return redisTemplate.execute(
            RedisScript.of(luaScript, Long.class),
            List.of(lockKey),
            List.of(lockValue)
        ).next().map(result -> result > 0);
    }

    /**
     * Execute a task under lock with automatic release.
     */
    public <T> Mono<T> executeWithLock(String resourceId, Duration lockTtl,
                                       Mono<T> task) {
        String lockKey = "lock:" + resourceId;
        String lockValue = UUID.randomUUID().toString();

        return tryLock(lockKey, lockValue, lockTtl)
            .flatMap(acquired -> {
                if (!acquired) {
                    return Mono.error(new LockAcquisitionException(
                        "Failed to acquire lock for " + resourceId));
                }
                return task
                    .doFinally(signal -> unlock(lockKey, lockValue).subscribe());
            });
    }
}
```

### Redisson (Recommended for Production)

```java
@Configuration
public class RedissonConfig {

    @Bean
    public RedissonClient redissonClient() {
        Config config = new Config();
        config.useSingleServer()
            .setAddress("redis://localhost:6379")
            .setConnectionMinimumIdleSize(4)
            .setConnectionPoolSize(16)
            .setTimeout(3000)
            .setRetryAttempts(3)
            .setRetryInterval(1500);
        return Redisson.create(config);
    }
}

@Service
@RequiredArgsConstructor
@Slf4j
public class RedissonLockService {

    private final RedissonClient redissonClient;

    /**
     * Redisson RLock: supports reentrant locking, auto-renewal (watchdog),
     * and fair locking. Handles edge cases that simple SET NX misses.
     */
    public <T> Mono<T> executeWithLock(String resourceId, Duration waitTime,
                                       Duration leaseTime, Mono<T> task) {
        RLockReactive lock = redissonClient.reactive().getLock("lock:" + resourceId);

        return lock.tryLock(waitTime.toMillis(), leaseTime.toMillis(), TimeUnit.MILLISECONDS)
            .flatMap(acquired -> {
                if (!acquired) {
                    return Mono.error(new LockAcquisitionException(
                        "Could not acquire lock for " + resourceId));
                }
                return task.doFinally(signal -> lock.unlock().subscribe());
            });
    }

    /**
     * Fair lock: FIFO ordering — no thread starvation.
     */
    public <T> Mono<T> executeWithFairLock(String resourceId, Mono<T> task) {
        RLockReactive lock = redissonClient.reactive().getFairLock("fair-lock:" + resourceId);
        return lock.lock(30, TimeUnit.SECONDS)
            .then(task)
            .doFinally(signal -> lock.unlock().subscribe());
    }
}
```

---

## Rate Limiting

### Sliding Window Rate Limiter

```java
@Service
@RequiredArgsConstructor
public class RedisRateLimiter {

    private final ReactiveRedisTemplate<String, Object> redisTemplate;

    /**
     * Sliding window rate limiter using sorted sets.
     * Each request = ZADD with timestamp score.
     * Count requests in window = ZRANGEBYSCORE.
     */
    public Mono<RateLimitResult> isAllowed(String clientId, int maxRequests,
                                           Duration window) {
        String key = "ratelimit:" + clientId;
        long now = Instant.now().toEpochMilli();
        long windowStart = now - window.toMillis();

        String luaScript = """
            -- Remove expired entries
            redis.call('ZREMRANGEBYSCORE', KEYS[1], 0, ARGV[1])
            -- Count current entries
            local count = redis.call('ZCARD', KEYS[1])
            if count < tonumber(ARGV[2]) then
                -- Add new entry
                redis.call('ZADD', KEYS[1], ARGV[3], ARGV[3] .. ':' .. math.random(1000000))
                redis.call('PEXPIRE', KEYS[1], ARGV[4])
                return {1, tonumber(ARGV[2]) - count - 1}
            else
                return {0, 0}
            end
            """;

        return redisTemplate.execute(
            RedisScript.of(luaScript, List.class),
            List.of(key),
            List.of(
                String.valueOf(windowStart),
                String.valueOf(maxRequests),
                String.valueOf(now),
                String.valueOf(window.toMillis())
            )
        ).next().map(result -> {
            List<Long> res = (List<Long>) result;
            return new RateLimitResult(res.get(0) == 1, res.get(1).intValue());
        });
    }
}

public record RateLimitResult(boolean allowed, int remaining) {}
```

### WebFlux Rate Limiter Filter

```java
@Component
@RequiredArgsConstructor
public class RateLimitWebFilter implements WebFilter {

    private final RedisRateLimiter rateLimiter;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String clientIp = Objects.requireNonNull(exchange.getRequest().getRemoteAddress())
            .getAddress().getHostAddress();

        return rateLimiter.isAllowed(clientIp, 100, Duration.ofMinutes(1))
            .flatMap(result -> {
                exchange.getResponse().getHeaders().add("X-RateLimit-Remaining",
                    String.valueOf(result.remaining()));

                if (!result.allowed()) {
                    exchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
                    exchange.getResponse().getHeaders().add("Retry-After", "60");
                    return exchange.getResponse().setComplete();
                }
                return chain.filter(exchange);
            });
    }
}
```

---

## Pub/Sub Patterns

### Reactive Pub/Sub Configuration

```java
@Configuration
public class RedisPubSubConfig {

    @Bean
    public ReactiveRedisMessageListenerContainer messageListenerContainer(
            ReactiveRedisConnectionFactory connectionFactory) {
        return new ReactiveRedisMessageListenerContainer(connectionFactory);
    }
}
```

### Publisher

```java
@Service
@RequiredArgsConstructor
public class RedisEventPublisher {

    private final ReactiveRedisTemplate<String, Object> redisTemplate;
    private final ObjectMapper objectMapper;

    public Mono<Long> publish(String channel, Object event) {
        try {
            String json = objectMapper.writeValueAsString(event);
            return redisTemplate.convertAndSend(channel, json);
        } catch (JsonProcessingException e) {
            return Mono.error(e);
        }
    }

    public Mono<Long> publishOrderUpdate(OrderStatusEvent event) {
        return publish("order:status:" + event.orderId(), event);
    }
}
```

### Subscriber

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class RedisEventSubscriber {

    private final ReactiveRedisMessageListenerContainer container;
    private final ObjectMapper objectMapper;

    /**
     * Subscribe to a channel pattern — returns a hot Flux.
     */
    public Flux<OrderStatusEvent> subscribeToOrderUpdates(String orderId) {
        return container.receive(ChannelTopic.of("order:status:" + orderId))
            .map(message -> {
                try {
                    return objectMapper.readValue(
                        message.getMessage().toString(), OrderStatusEvent.class);
                } catch (JsonProcessingException e) {
                    throw new RuntimeException("Deserialization failed", e);
                }
            })
            .doOnSubscribe(s -> log.info("Subscribed to order updates for {}", orderId))
            .doOnCancel(() -> log.info("Unsubscribed from order updates for {}", orderId));
    }

    /**
     * Pattern subscription — wildcard matching.
     */
    public Flux<Message<String, String>> subscribeToPattern(String pattern) {
        return container.receive(PatternTopic.of(pattern))
            .map(message -> message);
    }
}
```

### Server-Sent Events (SSE) with Redis Pub/Sub

```java
@RestController
@RequiredArgsConstructor
public class OrderStatusController {

    private final RedisEventSubscriber subscriber;

    @GetMapping(value = "/api/orders/{orderId}/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<OrderStatusEvent>> streamOrderStatus(
            @PathVariable String orderId) {
        return subscriber.subscribeToOrderUpdates(orderId)
            .map(event -> ServerSentEvent.<OrderStatusEvent>builder()
                .id(UUID.randomUUID().toString())
                .event("order-status")
                .data(event)
                .build());
    }
}
```

---

## Redis Streams

### Stream Producer

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class RedisStreamProducer {

    private final ReactiveRedisTemplate<String, Object> redisTemplate;

    /**
     * Append an event to a Redis Stream.
     * Returns the generated message ID (e.g., "1703275200000-0").
     */
    public Mono<RecordId> addToStream(String streamKey, Map<String, String> fields) {
        return redisTemplate.opsForStream()
            .add(StreamRecords.newRecord()
                .ofMap(fields)
                .withStreamKey(streamKey));
    }

    public Mono<RecordId> publishOrderEvent(OrderEvent event) {
        Map<String, String> fields = Map.of(
            "orderId", event.orderId(),
            "status", event.status().name(),
            "amount", event.amount().toString(),
            "timestamp", Instant.now().toString()
        );
        return addToStream("stream:orders", fields);
    }
}
```

### Stream Consumer Group

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class RedisStreamConsumer {

    private final ReactiveRedisTemplate<String, Object> redisTemplate;
    private static final String STREAM_KEY = "stream:orders";
    private static final String GROUP = "order-processors";
    private static final String CONSUMER = "consumer-" + UUID.randomUUID().toString().substring(0, 8);

    @PostConstruct
    public void init() {
        // Create consumer group if not exists
        redisTemplate.opsForStream()
            .createGroup(STREAM_KEY, ReadOffset.from("0"), GROUP)
            .onErrorResume(e -> {
                if (e.getMessage() != null && e.getMessage().contains("BUSYGROUP")) {
                    return Mono.just("OK"); // group already exists
                }
                return Mono.error(e);
            })
            .then(startConsuming())
            .subscribe();
    }

    private Mono<Void> startConsuming() {
        StreamOffset<String> offset = StreamOffset.create(STREAM_KEY, ReadOffset.lastConsumed());

        return redisTemplate.opsForStream()
            .read(Consumer.from(GROUP, CONSUMER),
                StreamReadOptions.empty().count(10).block(Duration.ofSeconds(5)),
                offset)
            .flatMap(this::processAndAck)
            .repeat()
            .then();
    }

    private Mono<Void> processAndAck(MapRecord<String, Object, Object> record) {
        log.info("Processing stream record id={}", record.getId());
        Map<Object, Object> fields = record.getValue();

        return processOrder(fields)
            .then(redisTemplate.opsForStream().acknowledge(STREAM_KEY, GROUP, record.getId()))
            .doOnSuccess(v -> log.debug("Acked record id={}", record.getId()))
            .then();
    }

    private Mono<Void> processOrder(Map<Object, Object> fields) {
        // Business logic
        return Mono.empty();
    }
}
```

### Stream Trimming (Prevent Unbounded Growth)

```java
// Keep only last 10,000 messages
redisTemplate.opsForStream()
    .trim(STREAM_KEY, 10_000);

// MAXLEN with approximate trimming (more efficient)
redisTemplate.opsForStream()
    .trim(STREAM_KEY, 10_000, true); // approximate = true
```

---

## Data Structure Patterns

### When to Use Which

| Structure | Use Case | Example |
|-----------|----------|---------|
| **String** | Simple key-value, counters, flags | Session tokens, feature flags, counters |
| **Hash** | Object storage, partial updates | User profiles, product details |
| **Set** | Unique collections, tags, membership | Online users, categories, friends |
| **Sorted Set** | Rankings, time-based data, rate limiting | Leaderboards, recent activity, sliding windows |
| **List** | Queues, recent items | Job queues, activity feeds |
| **HyperLogLog** | Cardinality estimation (approximate) | Unique visitors, unique events |
| **Stream** | Event log, message queue with consumer groups | Event sourcing, audit log |

### Hash — Object Storage

```java
/**
 * Hash: stores individual fields — efficient partial reads/writes.
 * Better than String(JSON) when you frequently update single fields.
 */
public Mono<Boolean> saveUserAsHash(UserProfile user) {
    String key = "user:hash:" + user.id();
    Map<String, String> fields = Map.of(
        "name", user.name(),
        "email", user.email(),
        "role", user.role(),
        "lastLogin", user.lastLogin().toString()
    );
    return redisTemplate.opsForHash()
        .putAll(key, fields)
        .then(redisTemplate.expire(key, Duration.ofHours(1)));
}

public Mono<Void> updateLastLogin(String userId) {
    return redisTemplate.opsForHash()
        .put("user:hash:" + userId, "lastLogin", Instant.now().toString())
        .then();
}
```

### Sorted Set — Leaderboard

```java
@Service
@RequiredArgsConstructor
public class LeaderboardService {

    private final ReactiveRedisTemplate<String, Object> redisTemplate;

    public Mono<Boolean> updateScore(String board, String userId, double score) {
        return redisTemplate.opsForZSet().add("leaderboard:" + board, userId, score);
    }

    public Flux<ZSetOperations.TypedTuple<Object>> getTopN(String board, int n) {
        return redisTemplate.opsForZSet()
            .reverseRangeWithScores("leaderboard:" + board, Range.closed(0L, (long) n - 1));
    }

    public Mono<Long> getRank(String board, String userId) {
        return redisTemplate.opsForZSet()
            .reverseRank("leaderboard:" + board, userId);
    }

    public Mono<Double> incrementScore(String board, String userId, double delta) {
        return redisTemplate.opsForZSet()
            .incrementScore("leaderboard:" + board, userId, delta);
    }
}
```

### HyperLogLog — Unique Counting

```java
/**
 * HyperLogLog: ~0.81% error rate, only 12KB per key regardless of cardinality.
 * Perfect for "how many unique users visited today?"
 */
public Mono<Long> addUniqueVisitor(String page, String visitorId) {
    String key = "hll:visitors:" + page + ":" + LocalDate.now();
    return redisTemplate.opsForHyperLogLog().add(key, visitorId);
}

public Mono<Long> getUniqueVisitors(String page) {
    String key = "hll:visitors:" + page + ":" + LocalDate.now();
    return redisTemplate.opsForHyperLogLog().size(key);
}

// Merge multiple days
public Mono<Long> getUniqueVisitorsRange(String page, LocalDate from, LocalDate to) {
    List<String> keys = from.datesUntil(to.plusDays(1))
        .map(d -> "hll:visitors:" + page + ":" + d)
        .toList();
    String destKey = "hll:visitors:" + page + ":merged";
    return redisTemplate.opsForHyperLogLog()
        .union(destKey, keys.toArray(String[]::new))
        .then(redisTemplate.opsForHyperLogLog().size(destKey));
}
```

### Set — Membership / Tags

```java
public Mono<Long> addToOnlineUsers(String userId) {
    return redisTemplate.opsForSet().add("online-users", userId);
}

public Mono<Long> removeFromOnlineUsers(String userId) {
    return redisTemplate.opsForSet().remove("online-users", userId);
}

public Mono<Boolean> isOnline(String userId) {
    return redisTemplate.opsForSet().isMember("online-users", userId);
}

// Mutual friends = intersection of two sets
public Flux<Object> getMutualFriends(String user1, String user2) {
    return redisTemplate.opsForSet().intersect("friends:" + user1, "friends:" + user2);
}
```

---

## Key Design

### Naming Convention

```
{service}:{entity}:{id}:{field}

# Examples:
user:profile:12345              # User profile object
user:session:abc-def            # Session data
order:detail:ORD-001            # Order detail
cache:product:SKU-100           # Cached product
lock:order:ORD-001              # Distributed lock
ratelimit:api:192.168.1.1       # Rate limit counter
leaderboard:daily:2024-01-15    # Sorted set leaderboard
hll:visitors:homepage:2024-01   # HyperLogLog
stream:orders                   # Redis Stream
```

### TTL Strategies

| Strategy | TTL | Use Case |
|----------|-----|----------|
| **Fixed TTL** | 30 min | API responses, computed values |
| **Sliding TTL** | Refresh on access | User sessions |
| **Event-driven** | Invalidate on write | Product catalog, user profiles |
| **Time-of-day** | Expire at midnight | Daily counters, leaderboards |
| **No TTL** | Permanent | Configuration, feature flags (manage manually) |

```java
// Sliding TTL: reset on every read
public <T> Mono<T> getWithSlidingTtl(String key, Class<T> type, Duration ttl) {
    return redisTemplate.opsForValue().get(key)
        .cast(type)
        .flatMap(value -> redisTemplate.expire(key, ttl).thenReturn(value));
}

// Time-of-day TTL: expire at midnight
public Duration ttlUntilMidnight() {
    LocalDateTime now = LocalDateTime.now();
    LocalDateTime midnight = now.toLocalDate().plusDays(1).atStartOfDay();
    return Duration.between(now, midnight);
}
```

### Eviction Policies

| Policy | Behavior | Best For |
|--------|----------|----------|
| `noeviction` | Return error when full | Critical data, must not lose |
| `allkeys-lru` | Evict least recently used | **General caching (recommended)** |
| `volatile-lru` | LRU among keys with TTL | Mix of cached + permanent data |
| `allkeys-lfu` | Evict least frequently used | Frequency-based access patterns |
| `volatile-ttl` | Evict shortest TTL first | Time-sensitive data |

```
# redis.conf
maxmemory 2gb
maxmemory-policy allkeys-lru
maxmemory-samples 10
```

---

## Serialization

### Jackson (Default — Human Readable)

```java
@Bean
public RedisSerializationContext<String, Object> jacksonContext() {
    Jackson2JsonRedisSerializer<Object> serializer =
        new Jackson2JsonRedisSerializer<>(objectMapper(), Object.class);
    return RedisSerializationContext.<String, Object>newSerializationContext(
            new StringRedisSerializer())
        .value(serializer)
        .build();
}
```

**Pros:** Human-readable, debuggable via `redis-cli`.
**Cons:** Larger payload, slower than binary formats.

### Kryo (Fast Binary)

```java
public class KryoRedisSerializer<T> implements RedisSerializer<T> {

    private static final ThreadLocal<Kryo> kryoThreadLocal = ThreadLocal.withInitial(() -> {
        Kryo kryo = new Kryo();
        kryo.setRegistrationRequired(false);
        kryo.setReferences(true);
        return kryo;
    });

    private final Class<T> type;

    public KryoRedisSerializer(Class<T> type) {
        this.type = type;
    }

    @Override
    public byte[] serialize(T value) throws SerializationException {
        if (value == null) return new byte[0];
        Output output = new Output(256, 65536);
        kryoThreadLocal.get().writeObject(output, value);
        return output.toBytes();
    }

    @Override
    public T deserialize(byte[] bytes) throws SerializationException {
        if (bytes == null || bytes.length == 0) return null;
        Input input = new Input(bytes);
        return kryoThreadLocal.get().readObject(input, type);
    }
}
```

**Pros:** 3-5x smaller than JSON, 2-3x faster.
**Cons:** Not human-readable, class evolution requires care.

### Protobuf (Schema-Driven Binary)

```java
public class ProtobufRedisSerializer<T extends MessageLite> implements RedisSerializer<T> {

    private final Parser<T> parser;

    public ProtobufRedisSerializer(Parser<T> parser) {
        this.parser = parser;
    }

    @Override
    public byte[] serialize(T value) {
        if (value == null) return new byte[0];
        return value.toByteArray();
    }

    @Override
    public T deserialize(byte[] bytes) {
        if (bytes == null || bytes.length == 0) return null;
        try {
            return parser.parseFrom(bytes);
        } catch (InvalidProtocolBufferException e) {
            throw new SerializationException("Protobuf deserialization failed", e);
        }
    }
}
```

**Pros:** Smallest payload, schema evolution, cross-language.
**Cons:** Requires `.proto` files, build step for code generation.

### Comparison

| Format | Size (relative) | Speed (relative) | Debuggable | Schema Evolution |
|--------|-----------------|-------------------|------------|-----------------|
| JSON (Jackson) | 1x (baseline) | 1x (baseline) | ✅ Yes | ⚠️ Manual |
| Kryo | 0.3-0.5x | 2-3x faster | ❌ No | ⚠️ Fragile |
| Protobuf | 0.2-0.4x | 2-4x faster | ❌ No | ✅ Built-in |

**Recommendation:** Use **Jackson** for development and most cases. Switch to **Protobuf** when payload size or cross-language compatibility matters.

---

## Redis Cluster & Sentinel

### Sentinel (High Availability)

```yaml
spring:
  data:
    redis:
      sentinel:
        master: mymaster
        nodes:
          - sentinel-1:26379
          - sentinel-2:26379
          - sentinel-3:26379
        password: ${SENTINEL_PASSWORD:}
      password: ${REDIS_PASSWORD:}
      lettuce:
        pool:
          max-active: 16
```

### Cluster

```yaml
spring:
  data:
    redis:
      cluster:
        nodes:
          - redis-1:6379
          - redis-2:6379
          - redis-3:6379
          - redis-4:6379
          - redis-5:6379
          - redis-6:6379
        max-redirects: 3
      lettuce:
        pool:
          max-active: 16
        cluster:
          refresh:
            adaptive: true
            period: 30s
```

### Cluster-Aware Key Design

```java
// Redis Cluster uses hash slots based on key. 
// Use {hash-tag} to ensure related keys land on same slot.

String userKey = "user:{user-123}:profile";
String sessionKey = "user:{user-123}:session";
String cartKey = "user:{user-123}:cart";
// All keys with {user-123} → same hash slot → same node
// This enables multi-key operations (MGET, transactions) on related data
```

---

## Session Management

```java
@Configuration
@EnableRedisWebSession(maxInactiveIntervalInSeconds = 1800)
public class SessionConfig {

    @Bean
    public ReactiveRedisSessionRepository sessionRepository(
            ReactiveRedisConnectionFactory factory) {
        return new ReactiveRedisIndexedSessionRepository(factory);
    }
}

// Access session in WebFlux controller
@GetMapping("/api/me")
public Mono<UserProfile> getCurrentUser(WebSession session) {
    String userId = session.getAttribute("userId");
    if (userId == null) {
        return Mono.error(new UnauthorizedException("No session"));
    }
    return userService.findById(userId);
}

@PostMapping("/api/login")
public Mono<Void> login(@RequestBody LoginRequest request, WebSession session) {
    return authService.authenticate(request)
        .flatMap(user -> {
            session.getAttributes().put("userId", user.id());
            session.getAttributes().put("role", user.role());
            return session.save();
        });
}
```

---

## Testing

### Testcontainers (Recommended)

```java
@SpringBootTest
@Testcontainers
class RedisCacheIntegrationTest {

    @Container
    static GenericContainer<?> redis = new GenericContainer<>(
            DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379);

    @DynamicPropertySource
    static void redisProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.data.redis.host", redis::getHost);
        registry.add("spring.data.redis.port", () -> redis.getMappedPort(6379));
    }

    @Autowired
    private ReactiveRedisTemplate<String, Object> redisTemplate;

    @Autowired
    private UserCacheService cacheService;

    @Test
    void shouldCacheUserOnFirstAccess() {
        // Given
        String userId = "test-user-1";
        UserProfile user = new UserProfile(userId, "Test User", "test@example.com");
        userRepository.save(user).block();

        // When — first call (cache miss)
        UserProfile result1 = cacheService.getUserById(userId).block();
        // When — second call (cache hit)
        UserProfile result2 = cacheService.getUserById(userId).block();

        // Then
        assertThat(result1).isEqualTo(result2);

        // Verify it's actually in Redis
        Object cached = redisTemplate.opsForValue().get("user:profile:" + userId).block();
        assertThat(cached).isNotNull();
    }

    @Test
    void shouldInvalidateCacheOnUpdate() {
        // Given
        String userId = "test-user-2";
        UserProfile user = new UserProfile(userId, "Original", "original@example.com");
        cacheService.getUserById(userId).block(); // populate cache

        // When
        UserProfile updated = new UserProfile(userId, "Updated", "updated@example.com");
        cacheService.updateUser(userId, updated).block();

        // Then — cache should be invalidated
        Boolean exists = redisTemplate.hasKey("user:profile:" + userId).block();
        assertThat(exists).isFalse();
    }

    @AfterEach
    void cleanup() {
        redisTemplate.execute(connection -> connection.serverCommands().flushAll())
            .blockLast();
    }
}
```

### Rate Limiter Test

```java
@Test
void shouldRateLimitAfterMaxRequests() {
    String clientId = "test-client";
    int maxRequests = 5;
    Duration window = Duration.ofSeconds(10);

    // First 5 requests should succeed
    for (int i = 0; i < maxRequests; i++) {
        RateLimitResult result = rateLimiter.isAllowed(clientId, maxRequests, window).block();
        assertThat(result.allowed()).isTrue();
    }

    // 6th request should be rejected
    RateLimitResult result = rateLimiter.isAllowed(clientId, maxRequests, window).block();
    assertThat(result.allowed()).isFalse();
}
```

---

## Common Anti-Patterns

### ❌ Big Keys

```java
// ❌ BAD: Storing 100MB JSON blob in a single key
redisTemplate.opsForValue().set("user:all", allUsersList); // 50K users = huge key

// ✅ GOOD: Split into individual keys or hash fields
users.forEach(user ->
    redisTemplate.opsForValue().set("user:profile:" + user.id(), user, Duration.ofHours(1)));

// ✅ GOOD: Use Hash for partial reads
redisTemplate.opsForHash().putAll("user:" + userId, userFieldMap);
```

**Rule of thumb:** No single key > 1MB. Ideally < 100KB.

### ❌ Hot Keys

```java
// ❌ BAD: Single counter accessed by all instances
redisTemplate.opsForValue().increment("global:page-views");
// Millions of requests hit ONE key → single Redis thread bottleneck

// ✅ GOOD: Shard the counter
int shard = ThreadLocalRandom.current().nextInt(16);
redisTemplate.opsForValue().increment("global:page-views:" + shard);

// Sum all shards when reading
Flux.range(0, 16)
    .flatMap(i -> redisTemplate.opsForValue().get("global:page-views:" + i))
    .map(v -> v != null ? (Long) v : 0L)
    .reduce(Long::sum);
```

### ❌ Thundering Herd

```java
// ❌ BAD: Popular cache key expires → 1000 requests hit DB simultaneously
public Mono<Product> getProduct(String id) {
    return redisTemplate.opsForValue().get("product:" + id)
        .switchIfEmpty(productRepository.findById(id) // 1000 threads hit this
            .flatMap(p -> redisTemplate.opsForValue().set("product:" + id, p).thenReturn(p)));
}

// ✅ GOOD: Mutex/lock on cache miss
public Mono<Product> getProductSafe(String id) {
    String cacheKey = "product:" + id;
    return redisTemplate.opsForValue().get(cacheKey)
        .cast(Product.class)
        .switchIfEmpty(
            lockService.executeWithLock("cache-fill:" + id, Duration.ofSeconds(10),
                // Only ONE instance fills the cache
                productRepository.findById(id)
                    .flatMap(p -> redisTemplate.opsForValue()
                        .set(cacheKey, p, Duration.ofMinutes(30))
                        .thenReturn(p))
            )
        );
}

// ✅ ALSO GOOD: Jittered TTL — prevents simultaneous expiry
Duration jitteredTtl = Duration.ofMinutes(30)
    .plus(Duration.ofSeconds(ThreadLocalRandom.current().nextInt(300)));
```

### ❌ No TTL on Cache Keys

```java
// ❌ BAD: Cache grows forever until OOM
redisTemplate.opsForValue().set("user:" + userId, user);

// ✅ GOOD: Always set TTL
redisTemplate.opsForValue().set("user:" + userId, user, Duration.ofMinutes(30));
```

### ❌ Using KEYS Command in Production

```java
// ❌ BAD: KEYS * blocks Redis (O(N) over entire keyspace)
redisTemplate.keys("user:*");

// ✅ GOOD: Use SCAN for iteration (non-blocking, cursor-based)
redisTemplate.scan(ScanOptions.scanOptions().match("user:*").count(100).build());
```

### ❌ Storing Sensitive Data Without Encryption

```java
// ❌ BAD: Plain text PII in Redis
redisTemplate.opsForValue().set("user:session:" + id, sessionWithPII);

// ✅ GOOD: Encrypt sensitive fields before storing
String encrypted = encryptionService.encrypt(sensitiveData);
redisTemplate.opsForValue().set("user:session:" + id, encrypted, Duration.ofMinutes(30));
```

---

## Key Design Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Serialization | Jackson for most; Protobuf for high-volume | Debuggability vs performance |
| TTL | Always set; jitter for popular keys | Prevents memory leak + thundering herd |
| Max memory | 70-80% of available RAM | Leave room for COW during BGSAVE |
| Eviction | `allkeys-lru` for cache workloads | Most predictable behavior |
| Connection pool | `max-active=16`, `min-idle=4` | Balance connection reuse vs overhead |
| Cluster vs Sentinel | Sentinel for HA; Cluster for >25GB or >100K ops/s | Don't over-engineer |
| Pub/Sub vs Streams | Pub/Sub for fire-and-forget; Streams for durability | Streams survive restarts |