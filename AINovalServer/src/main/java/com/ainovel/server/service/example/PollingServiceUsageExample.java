package com.ainovel.server.service.example;

import com.ainovel.server.service.impl.PollingTaskServiceImpl;
import com.ainovel.server.web.dto.PollingTaskStatusDto;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

/**
 * 轮询服务使用示例
 * 展示如何在实际业务中使用PollingTaskService
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PollingServiceUsageExample {

    private final PollingTaskServiceImpl pollingTaskService;

    // ============================================================================
    // 示例1: 小说导入任务
    // ============================================================================

    /**
     * 开始小说导入并返回任务ID
     */
    public String startNovelImport(String userId, String fileName, byte[] fileContent) {
        log.info("开始小说导入: userId={}, fileName={}", userId, fileName);

        // 创建任务
        Map<String, Object> metadata = new HashMap<>();
        metadata.put("userId", userId);
        metadata.put("fileName", fileName);
        metadata.put("fileSize", fileContent.length);

        String taskId = pollingTaskService.createTask("NOVEL_IMPORT", metadata);

        // 异步执行导入任务
        CompletableFuture.runAsync(() -> executeImportTask(taskId, fileContent));

        return taskId;
    }

    /**
     * 执行导入任务
     */
    private void executeImportTask(String taskId, byte[] fileContent) {
        try {
            // 更新为运行中
            pollingTaskService.updateTaskStatus(taskId, "RUNNING", 0, "开始解析文件...");

            // 模拟分章节处理
            int totalChapters = 100;
            for (int i = 1; i <= totalChapters; i++) {
                // 模拟处理章节
                processChapter(i);

                // 更新进度
                int progress = (int) ((double) i / totalChapters * 100);
                pollingTaskService.updateTaskStatus(
                        taskId,
                        "RUNNING",
                        progress,
                        String.format("正在导入第 %d/%d 章", i, totalChapters)
                );

                // 模拟处理时间
                Thread.sleep(100);
            }

            // 构建结果
            Map<String, Object> result = new HashMap<>();
            result.put("novelId", "novel_" + System.currentTimeMillis());
            result.put("totalChapters", totalChapters);
            result.put("totalWords", totalChapters * 3000);

            // 标记完成
            pollingTaskService.updateTaskStatus(taskId, "COMPLETED", 100, "导入完成");
            pollingTaskService.updateTaskResult(taskId, result);

            log.info("导入任务完成: taskId={}", taskId);

        } catch (Exception e) {
            log.error("导入任务失败: taskId={}", taskId, e);
            pollingTaskService.updateTaskError(taskId, "导入失败: " + e.getMessage(), getStackTrace(e));
        }
    }

    private void processChapter(int chapterIndex) {
        // 实际的章节处理逻辑
        log.debug("处理章节: {}", chapterIndex);
    }

    // ============================================================================
    // 示例2: AI生成任务
    // ============================================================================

    /**
     * 开始AI内容生成任务
     */
    public String startAIGeneration(String userId, String novelId, String sceneId, String prompt) {
        log.info("开始AI生成: userId={}, novelId={}, sceneId={}", userId, novelId, sceneId);

        // 创建任务
        Map<String, Object> metadata = new HashMap<>();
        metadata.put("userId", userId);
        metadata.put("novelId", novelId);
        metadata.put("sceneId", sceneId);
        metadata.put("promptLength", prompt.length());

        String taskId = pollingTaskService.createTask("AI_GENERATION", metadata);

        // 异步执行生成任务
        CompletableFuture.runAsync(() -> executeAIGenerationTask(taskId, prompt));

        return taskId;
    }

    /**
     * 执行AI生成任务
     */
    private void executeAIGenerationTask(String taskId, String prompt) {
        try {
            // 更新为运行中
            pollingTaskService.updateTaskStatus(taskId, "RUNNING", 0, "准备调用AI模型...");

            // 模拟AI生成过程
            pollingTaskService.updateTaskStatus(taskId, "RUNNING", 20, "正在生成内容...");
            Thread.sleep(2000);

            pollingTaskService.updateTaskStatus(taskId, "RUNNING", 50, "内容生成中...");
            Thread.sleep(3000);

            pollingTaskService.updateTaskStatus(taskId, "RUNNING", 80, "完善细节...");
            Thread.sleep(1000);

            // 生成完成
            String generatedContent = "这是AI生成的内容示例...";
            Map<String, Object> result = new HashMap<>();
            result.put("content", generatedContent);
            result.put("wordCount", generatedContent.length());
            result.put("modelUsed", "gpt-4");

            pollingTaskService.updateTaskStatus(taskId, "COMPLETED", 100, "生成完成");
            pollingTaskService.updateTaskResult(taskId, result);

            log.info("AI生成任务完成: taskId={}", taskId);

        } catch (Exception e) {
            log.error("AI生成任务失败: taskId={}", taskId, e);
            pollingTaskService.updateTaskError(taskId, "生成失败: " + e.getMessage(), getStackTrace(e));
        }
    }

    // ============================================================================
    // 示例3: 批量操作任务
    // ============================================================================

    /**
     * 开始批量场景处理任务
     */
    public String startBatchSceneProcessing(String userId, String novelId, int sceneCount) {
        log.info("开始批量处理场景: userId={}, novelId={}, sceneCount={}", userId, novelId, sceneCount);

        // 创建任务
        Map<String, Object> metadata = new HashMap<>();
        metadata.put("userId", userId);
        metadata.put("novelId", novelId);
        metadata.put("totalScenes", sceneCount);

        String taskId = pollingTaskService.createTask("BATCH_PROCESSING", metadata);

        // 异步执行
        CompletableFuture.runAsync(() -> executeBatchProcessing(taskId, novelId, sceneCount));

        return taskId;
    }

    /**
     * 执行批量处理
     */
    private void executeBatchProcessing(String taskId, String novelId, int sceneCount) {
        try {
            pollingTaskService.updateTaskStatus(taskId, "RUNNING", 0, "开始批量处理...");

            int successCount = 0;
            int failCount = 0;

            for (int i = 1; i <= sceneCount; i++) {
                try {
                    // 处理单个场景
                    processScene(novelId, "scene_" + i);
                    successCount++;

                    // 更新进度
                    int progress = (int) ((double) i / sceneCount * 100);
                    pollingTaskService.updateTaskStatus(
                            taskId,
                            "RUNNING",
                            progress,
                            String.format("已处理 %d/%d 个场景 (成功: %d, 失败: %d)",
                                    i, sceneCount, successCount, failCount)
                    );

                    Thread.sleep(200);

                } catch (Exception e) {
                    failCount++;
                    log.warn("场景处理失败: scene_{}", i, e);
                }
            }

            // 构建结果
            Map<String, Object> result = new HashMap<>();
            result.put("totalProcessed", sceneCount);
            result.put("successCount", successCount);
            result.put("failCount", failCount);
            result.put("novelId", novelId);

            pollingTaskService.updateTaskStatus(taskId, "COMPLETED", 100, "批量处理完成");
            pollingTaskService.updateTaskResult(taskId, result);

            log.info("批量处理完成: taskId={}, success={}, fail={}", taskId, successCount, failCount);

        } catch (Exception e) {
            log.error("批量处理失败: taskId={}", taskId, e);
            pollingTaskService.updateTaskError(taskId, "批量处理失败: " + e.getMessage(), getStackTrace(e));
        }
    }

    private void processScene(String novelId, String sceneId) throws Exception {
        // 实际的场景处理逻辑
        log.debug("处理场景: novelId={}, sceneId={}", novelId, sceneId);
    }

    // ============================================================================
    // 示例4: 可取消的长时任务
    // ============================================================================

    /**
     * 开始可取消的长时任务
     */
    public String startLongRunningTask(String userId, int durationSeconds) {
        log.info("开始长时任务: userId={}, duration={}s", userId, durationSeconds);

        Map<String, Object> metadata = new HashMap<>();
        metadata.put("userId", userId);
        metadata.put("durationSeconds", durationSeconds);

        String taskId = pollingTaskService.createTask("LONG_RUNNING", metadata);

        // 异步执行
        CompletableFuture.runAsync(() -> executeLongRunningTask(taskId, durationSeconds));

        return taskId;
    }

    /**
     * 执行长时任务（支持取消）
     */
    private void executeLongRunningTask(String taskId, int durationSeconds) {
        try {
            pollingTaskService.updateTaskStatus(taskId, "RUNNING", 0, "任务开始执行...");

            for (int i = 0; i < durationSeconds; i++) {
                // 检查任务是否被取消
                Mono<PollingTaskStatusDto> statusMono = pollingTaskService.getTaskStatus(taskId);
                PollingTaskStatusDto status = statusMono.block();

                if (status != null && status.isCancelled()) {
                    log.info("任务被取消: taskId={}", taskId);
                    return;
                }

                // 执行任务
                Thread.sleep(1000);

                // 更新进度
                int progress = (int) ((double) (i + 1) / durationSeconds * 100);
                int remainingSeconds = durationSeconds - i - 1;

                pollingTaskService.updateTaskStatus(
                        taskId,
                        "RUNNING",
                        progress,
                        String.format("执行中... (剩余 %d 秒)", remainingSeconds)
                );
            }

            // 任务完成
            Map<String, Object> result = new HashMap<>();
            result.put("executionTime", durationSeconds);
            result.put("completedAt", System.currentTimeMillis());

            pollingTaskService.updateTaskStatus(taskId, "COMPLETED", 100, "任务完成");
            pollingTaskService.updateTaskResult(taskId, result);

            log.info("长时任务完成: taskId={}", taskId);

        } catch (InterruptedException e) {
            log.warn("任务被中断: taskId={}", taskId);
            Thread.currentThread().interrupt();
            pollingTaskService.updateTaskError(taskId, "任务被中断", e.getMessage());
        } catch (Exception e) {
            log.error("长时任务失败: taskId={}", taskId, e);
            pollingTaskService.updateTaskError(taskId, "任务失败: " + e.getMessage(), getStackTrace(e));
        }
    }

    // ============================================================================
    // 示例5: 带子任务的复杂任务
    // ============================================================================

    /**
     * 开始带子任务的复杂任务
     */
    public String startComplexTask(String userId, String novelId) {
        log.info("开始复杂任务: userId={}, novelId={}", userId, novelId);

        Map<String, Object> metadata = new HashMap<>();
        metadata.put("userId", userId);
        metadata.put("novelId", novelId);

        String parentTaskId = pollingTaskService.createTask("COMPLEX_TASK", metadata);

        // 异步执行
        CompletableFuture.runAsync(() -> executeComplexTask(parentTaskId, novelId));

        return parentTaskId;
    }

    /**
     * 执行复杂任务
     */
    private void executeComplexTask(String parentTaskId, String novelId) {
        try {
            pollingTaskService.updateTaskStatus(parentTaskId, "RUNNING", 0, "开始执行复杂任务...");

            // 子任务1: 数据分析
            String task1 = pollingTaskService.createTask("SUBTASK_ANALYZE", new HashMap<>());
            pollingTaskService.updateTaskStatus(parentTaskId, "RUNNING", 20, "执行子任务1: 数据分析");
            executeSubTask(task1, "分析数据");
            pollingTaskService.updateTaskStatus(task1, "COMPLETED", 100, "分析完成");

            // 子任务2: 内容处理
            String task2 = pollingTaskService.createTask("SUBTASK_PROCESS", new HashMap<>());
            pollingTaskService.updateTaskStatus(parentTaskId, "RUNNING", 50, "执行子任务2: 内容处理");
            executeSubTask(task2, "处理内容");
            pollingTaskService.updateTaskStatus(task2, "COMPLETED", 100, "处理完成");

            // 子任务3: 结果生成
            String task3 = pollingTaskService.createTask("SUBTASK_GENERATE", new HashMap<>());
            pollingTaskService.updateTaskStatus(parentTaskId, "RUNNING", 80, "执行子任务3: 结果生成");
            executeSubTask(task3, "生成结果");
            pollingTaskService.updateTaskStatus(task3, "COMPLETED", 100, "生成完成");

            // 主任务完成
            Map<String, Object> result = new HashMap<>();
            result.put("novelId", novelId);
            result.put("subtasks", new String[]{task1, task2, task3});
            result.put("completedSubtasks", 3);

            pollingTaskService.updateTaskStatus(parentTaskId, "COMPLETED", 100, "所有子任务完成");
            pollingTaskService.updateTaskResult(parentTaskId, result);

            log.info("复杂任务完成: parentTaskId={}", parentTaskId);

        } catch (Exception e) {
            log.error("复杂任务失败: parentTaskId={}", parentTaskId, e);
            pollingTaskService.updateTaskError(parentTaskId, "任务失败: " + e.getMessage(), getStackTrace(e));
        }
    }

    private void executeSubTask(String taskId, String action) throws InterruptedException {
        log.debug("执行子任务: taskId={}, action={}", taskId, action);
        pollingTaskService.updateTaskStatus(taskId, "RUNNING", 0, action);
        Thread.sleep(2000);
    }

    // ============================================================================
    // 工具方法
    // ============================================================================

    private String getStackTrace(Exception e) {
        StringBuilder sb = new StringBuilder();
        for (StackTraceElement element : e.getStackTrace()) {
            sb.append(element.toString()).append("\n");
        }
        return sb.toString();
    }

    /**
     * 获取任务状态（供Controller调用）
     */
    public Mono<PollingTaskStatusDto> getTaskStatus(String taskId) {
        return pollingTaskService.getTaskStatus(taskId);
    }

    /**
     * 取消任务（供Controller调用）
     */
    public Mono<Boolean> cancelTask(String taskId) {
        return pollingTaskService.cancelTask(taskId);
    }

    /**
     * 清理已完成的任务
     */
    public int cleanupFinishedTasks() {
        return pollingTaskService.cleanupFinishedTasks();
    }

    /**
     * 获取活跃任务数量
     */
    public int getActiveTaskCount() {
        return pollingTaskService.getActiveTaskCount();
    }
}
