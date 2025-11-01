# API轮询功能设计总结

## 📋 功能概述

本次设计为 AINovalWriter 项目实现了一套完整的 API 轮询功能，包括前端（Flutter）和后端（Spring Boot）的完整实现。

## 🎯 设计目标

✅ **通用性** - 可用于各种异步任务监控场景  
✅ **灵活性** - 支持多种轮询策略和配置  
✅ **高效性** - 智能轮询间隔，减少不必要请求  
✅ **可靠性** - 完善的错误处理和重试机制  
✅ **易用性** - 简洁的API设计，方便集成

## 📂 交付文件

### 前端文件

| 文件 | 说明 | 状态 |
|------|------|------|
| `AINoval/lib/services/polling_service.dart` | 核心轮询服务实现 | ✅ 已创建 |
| `AINoval/lib/services/polling_service_example.dart` | 详细使用示例（8个场景） | ✅ 已创建 |
| `AINoval/test/services/polling_service_test.dart` | 单元测试（9个测试组） | ✅ 已创建 |

### 后端文件

| 文件 | 说明 | 状态 |
|------|------|------|
| `AINovalServer/.../PollingTaskStatusDto.java` | 任务状态DTO | ✅ 已创建 |
| `AINovalServer/.../LongPollingRequest.java` | 长轮询请求DTO | ✅ 已创建 |
| `AINovalServer/.../PollingTaskService.java` | 轮询服务接口 | ✅ 已创建 |
| `AINovalServer/.../PollingTaskServiceImpl.java` | 轮询服务实现 | ✅ 已创建 |
| `AINovalServer/.../PollingController.java` | 轮询控制器 | ✅ 已创建 |
| `AINovalServer/.../PollingServiceUsageExample.java` | 后端使用示例（5个场景） | ✅ 已创建 |

### 文档文件

| 文件 | 说明 | 状态 |
|------|------|------|
| `API_POLLING_DESIGN.md` | 详细设计文档 | ✅ 已创建 |
| `POLLING_INTEGRATION_GUIDE.md` | 集成指南 | ✅ 已创建 |
| `POLLING_FEATURE_SUMMARY.md` | 本文档 | ✅ 已创建 |

## 🔧 核心功能

### 1. 轮询服务 (PollingService)

**主要特性**:
- ✅ 支持 Future 和 Stream 两种使用模式
- ✅ 可配置的轮询间隔和超时
- ✅ 指数退避策略（智能轮询）
- ✅ 灵活的停止条件
- ✅ 完善的错误处理和重试
- ✅ 实时进度回调

**配置预设**:
```dart
PollingConfig.fast()      // 1秒间隔 - 快速任务
PollingConfig.standard()  // 3秒间隔 - 标准任务
PollingConfig.slow()      // 10秒间隔 - 慢速任务
PollingConfig.smart()     // 智能退避 - 长时任务
```

### 2. 轮询管理器 (PollingManager)

**主要特性**:
- ✅ 全局单例模式
- ✅ 管理多个并发轮询任务
- ✅ 统一的任务标识和生命周期管理
- ✅ 统计信息和监控
- ✅ 批量停止功能

### 3. 后端支持

**主要功能**:
- ✅ 任务状态管理（内存存储，可扩展到Redis）
- ✅ 短轮询接口（立即返回）
- ✅ 长轮询接口（等待状态变化）
- ✅ 任务取消和清理
- ✅ 版本控制（检测状态变化）

## 📊 API接口

### 前端API

```dart
// 创建轮询服务
final polling = PollingService<T>();

// 启动轮询（Future模式）
final result = await polling.start(
  fetcher: () => apiClient.get('/api/status'),
  parser: (data) => MyModel.fromJson(data),
  stopCondition: (result) => result.data?.isComplete ?? false,
  config: PollingConfig.smart(),
  onUpdate: (result) { /* 更新UI */ },
);

// 启动轮询（Stream模式）
final stream = polling.startStream(
  fetcher: () => apiClient.get('/api/status'),
  parser: (data) => MyModel.fromJson(data),
  stopCondition: (result) => result.data?.isComplete ?? false,
  config: PollingConfig.standard(),
);

// 使用管理器
final manager = PollingManager();
await manager.startPolling(
  id: 'task_123',
  fetcher: () => apiClient.get('/api/status'),
  parser: (data) => MyModel.fromJson(data),
  stopCondition: (result) => result.data?.isComplete ?? false,
  config: PollingConfig.smart(),
);

// 停止轮询
manager.stopPolling('task_123');
manager.stopAll();
```

### 后端API

```java
// 短轮询 - 立即返回当前状态
POST /api/v1/polling/tasks/{taskId}/status

// 长轮询 - 等待状态变化或超时
POST /api/v1/polling/tasks/long-poll
{
  "taskId": "task_123",
  "lastVersion": "version_abc",
  "timeoutSeconds": 30,
  "onlyOnChange": true
}

// 取消任务
POST /api/v1/polling/tasks/{taskId}/cancel

// 检查任务是否存在
POST /api/v1/polling/tasks/{taskId}/exists

// 清理任务
POST /api/v1/polling/tasks/{taskId}/cleanup
```

## 💡 使用场景

### 1. 小说导入进度监控

**前端**:
```dart
final polling = PollingService<ImportStatus>();
await polling.start(
  fetcher: () => apiClient.get('/novels/import/$jobId/status'),
  parser: (data) => ImportStatus.fromJson(data),
  stopCondition: (result) => 
    result.data?.status == 'completed' || 
    result.data?.status == 'failed',
  config: PollingConfig.smart(initialIntervalMs: 1000),
  onUpdate: (result) {
    print('进度: ${result.data?.progress}%');
  },
);
```

**后端**:
```java
String taskId = pollingTaskService.createTask("NOVEL_IMPORT", metadata);
CompletableFuture.runAsync(() -> {
    for (int i = 0; i < totalChapters; i++) {
        processChapter(i);
        pollingTaskService.updateTaskStatus(
            taskId, "RUNNING", progress, "正在导入..."
        );
    }
    pollingTaskService.updateTaskStatus(taskId, "COMPLETED", 100, "完成");
});
return taskId;
```

### 2. AI生成任务监控

```dart
final manager = PollingManager();
await manager.startPolling<AITaskStatus>(
  id: 'ai_$taskId',
  fetcher: () => apiClient.post('/polling/tasks/$taskId/status'),
  parser: (data) => AITaskStatus.fromJson(data),
  stopCondition: (result) => result.data?.isFinished ?? false,
  config: PollingConfig.standard(),
);
```

### 3. 批量操作进度跟踪

```dart
// 同时监控多个任务
for (final taskId in taskIds) {
  manager.startPolling(
    id: 'batch_$taskId',
    fetcher: () => apiClient.get('/tasks/$taskId/status'),
    parser: (data) => TaskStatus.fromJson(data),
    stopCondition: (result) => result.data?.isComplete ?? false,
    config: PollingConfig.fast(),
  );
}

// 获取统计
print('活跃任务数: ${manager.activeCount}');
```

## 🎨 核心设计模式

### 1. 指数退避策略

```
轮询间隔示例（初始1秒，倍数1.5，最大30秒）:
第1次: 1秒
第2次: 1.5秒
第3次: 2.25秒
第4次: 3.375秒
第5次: 5.06秒
...
第N次: 30秒（达到最大值）
```

**优势**: 
- 短时任务快速完成（高频轮询）
- 长时任务减少请求（低频轮询）
- 自动适应任务时长

### 2. 灵活的停止条件

```dart
stopCondition: (result) {
  // 1. 错误立即停止
  if (result.hasError) return true;
  
  // 2. 数据检查
  if (result.data == null) return false;
  
  // 3. 业务逻辑
  if (result.data.status == 'completed') return true;
  if (result.data.progress >= 100) return true;
  
  // 4. 安全保护
  if (result.attemptNumber > 100) return true;
  
  return false;
}
```

### 3. 长轮询优化

**原理**: 服务器端保持连接直到状态变化或超时

**优势**:
- 减少请求次数（从每3秒一次 → 状态变化时才返回）
- 降低服务器负载
- 提高实时性

**实现**:
```java
private Mono<PollingTaskStatusDto> pollWithRetry(...) {
    return Mono.defer(() -> {
        String currentVersion = taskVersionMap.get(taskId);
        // 版本号不同或任务完成 → 立即返回
        if (!currentVersion.equals(lastVersion) || status.isFinished()) {
            return Mono.just(status);
        }
        // 否则等待500ms后重试
        return Mono.delay(Duration.ofMillis(500))
                .flatMap(tick -> pollWithRetry(...));
    });
}
```

## 📈 性能优化

### 1. 请求频率控制

| 策略 | 初始间隔 | 最大间隔 | 适用场景 |
|------|----------|----------|----------|
| Fast | 1秒 | 1秒 | < 10秒的快速任务 |
| Standard | 3秒 | 3秒 | 10秒-5分钟的中等任务 |
| Slow | 10秒 | 10秒 | > 5分钟的长时任务 |
| Smart | 1秒 | 30秒 | 时长不确定的任务 |

### 2. 错误处理策略

```dart
PollingConfig(
  continueOnError: true,         // 出错继续轮询
  maxConsecutiveErrors: 5,       // 最多连续5次错误
)
```

**流程**:
```
正常 → 错误1 → 错误2 → 正常 (重置计数) → 错误1 → 错误2 → 错误3 → 错误4 → 错误5 → 停止
```

### 3. 资源管理

```dart
class MyWidget extends StatefulWidget {
  @override
  void dispose() {
    _pollingManager.stopAll();  // 清理所有轮询
    super.dispose();
  }
}
```

## 🔒 安全性

### 1. 超时保护

```dart
PollingConfig(
  timeoutMs: 300000,    // 5分钟总超时
  maxAttempts: 100,     // 或限制最大尝试次数
)
```

### 2. 并发限制

```dart
class PollingManager {
  static const int MAX_CONCURRENT_POLLS = 10;
  
  Future<void> startPolling(...) async {
    if (activeCount >= MAX_CONCURRENT_POLLS) {
      throw StateError('超过最大并发轮询数量');
    }
    // ...
  }
}
```

### 3. 后端鉴权

```java
@PostMapping("/tasks/{taskId}/status")
public Mono<PollingTaskStatusDto> getTaskStatus(
    @PathVariable String taskId,
    @CurrentUser String userId  // JWT认证
) {
    // 验证任务属于当前用户
    return pollingTaskService.getTaskStatus(taskId)
        .filter(task -> task.getUserId().equals(userId))
        .switchIfEmpty(Mono.error(new UnauthorizedException()));
}
```

## 🧪 测试覆盖

### 前端测试（9个测试组，共30+测试用例）

1. ✅ PollingConfig 配置测试
2. ✅ PollingResult 结果测试
3. ✅ PollingService 基础功能测试
4. ✅ 错误处理测试
5. ✅ 超时控制测试
6. ✅ Stream模式测试
7. ✅ PollingManager 管理器测试
8. ✅ 并发任务测试
9. ✅ 停止条件测试

### 运行测试

```bash
cd AINoval
flutter test test/services/polling_service_test.dart
```

## 📚 文档

### 1. 设计文档
- 📄 `API_POLLING_DESIGN.md` - 详细的技术设计文档
  - 架构设计
  - API规范
  - 使用场景
  - 最佳实践
  - 性能优化

### 2. 集成指南
- 📄 `POLLING_INTEGRATION_GUIDE.md` - 项目集成指南
  - 前端集成步骤
  - 后端集成步骤
  - 完整示例代码
  - 故障排查

### 3. 代码示例
- 📄 `polling_service_example.dart` - 前端示例（8个场景）
- 📄 `PollingServiceUsageExample.java` - 后端示例（5个场景）

## 🔄 与现有系统集成

### 1. 替换现有轮询逻辑

**原代码** (ai_task_center_panel.dart):
```dart
_pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
  // 手动轮询逻辑
  for (final t in runningTasks) {
    final status = await _repo.getTaskStatus(taskId);
    // ...
  }
});
```

**新代码**:
```dart
_pollingManager.startPollingStream(
  id: 'task_fallback',
  fetcher: () => _repo.getTaskStatus(taskId),
  stopCondition: (result) => result.data?.isFinished ?? false,
  config: PollingConfig.smart(initialIntervalMs: 30000),
).listen((result) {
  // 处理结果
});
```

### 2. 与BLoC集成

```dart
class EditorBloc extends Bloc<EditorEvent, EditorState> {
  final _pollingManager = PollingManager();
  
  EditorBloc() : super(EditorInitial()) {
    on<StartTaskPolling>((event, emit) async {
      await _pollingManager.startPolling(
        id: 'task_${event.taskId}',
        fetcher: () => apiClient.post('/polling/tasks/${event.taskId}/status'),
        stopCondition: (result) => result.data?.isFinished ?? false,
        onUpdate: (result) {
          add(TaskStatusUpdated(result.data!));
        },
      );
    });
  }
  
  @override
  Future<void> close() {
    _pollingManager.stopAll();
    return super.close();
  }
}
```

### 3. SecurityConfig配置

在 `AINovalServer/src/main/java/com/ainovel/server/config/SecurityConfig.java` 中添加：

```java
@Bean
public SecurityWebFilterChain securityWebFilterChain(ServerHttpSecurity http) {
    return http
        // ...
        .pathMatchers("/api/v1/polling/**").authenticated()
        // ...
        .build();
}
```

## 🚀 扩展建议

### 1. Redis支持（生产环境）

```java
@Service
public class RedisPollingTaskService implements PollingTaskService {
    private final ReactiveRedisTemplate<String, PollingTaskStatusDto> redisTemplate;
    
    @Override
    public Mono<PollingTaskStatusDto> getTaskStatus(String taskId) {
        return redisTemplate.opsForValue()
            .get("polling:task:" + taskId);
    }
    
    // 设置24小时过期
    public void updateTaskStatus(...) {
        redisTemplate.opsForValue()
            .set(key, task, Duration.ofHours(24))
            .subscribe();
    }
}
```

### 2. 监控和统计

```dart
// 前端监控
class PollingMonitor {
  static void logStatistics() {
    final stats = PollingManager().getAllStatistics();
    AppLogger.i('PollingMonitor', '活跃轮询: ${stats['activeCount']}');
    AppLogger.i('PollingMonitor', '总尝试次数: ${stats['totalAttempts']}');
  }
}
```

```java
// 后端监控
@Scheduled(fixedRate = 60000)
public void logStatistics() {
    int active = pollingTaskService.getActiveTaskCount();
    log.info("活跃任务数: {}", active);
}
```

### 3. 定时清理

```java
@Scheduled(fixedRate = 3600000)  // 每小时
public void cleanupOldTasks() {
    int cleaned = pollingTaskService.cleanupFinishedTasks();
    log.info("清理已完成任务: {} 个", cleaned);
}
```

## ✅ 验收标准

- [x] 前端核心服务实现完成
- [x] 前端管理器实现完成
- [x] 后端服务接口实现完成
- [x] 后端控制器实现完成
- [x] 前端单元测试完成（30+用例）
- [x] 前端使用示例完成（8个场景）
- [x] 后端使用示例完成（5个场景）
- [x] 设计文档完成
- [x] 集成指南完成
- [x] 支持多种轮询策略
- [x] 支持指数退避
- [x] 支持长轮询优化
- [x] 支持错误处理和重试
- [x] 支持超时控制
- [x] 支持取消机制
- [x] 代码注释完整
- [x] 符合项目代码规范

## 🎉 总结

本次设计交付了一套完整、可靠、高效的API轮询解决方案，具有以下特点：

1. **完整性** - 包含前后端完整实现和详细文档
2. **通用性** - 可用于各种异步任务监控场景
3. **灵活性** - 支持多种配置和使用模式
4. **高效性** - 智能轮询策略减少不必要请求
5. **可靠性** - 完善的错误处理和边界保护
6. **易用性** - 简洁的API和丰富的示例
7. **可扩展** - 支持Redis、监控等扩展
8. **可维护** - 完整的文档和测试

推荐在项目中**优先使用SSE实现实时推送**，将本轮询功能作为**可靠的降级方案**。

---

**创建时间**: 2025-01-XX  
**版本**: 1.0.0  
**作者**: AI Assistant  
**项目**: AINovalWriter
