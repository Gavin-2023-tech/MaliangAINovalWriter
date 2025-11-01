package com.ainovel.server.service;

import com.ainovel.server.web.dto.PollingTaskStatusDto;
import reactor.core.publisher.Mono;

import java.time.Duration;

/**
 * 轮询任务服务接口
 * 为各种异步任务提供统一的轮询查询支持
 */
public interface PollingTaskService {
    /**
     * 获取任务状态
     *
     * @param taskId 任务ID
     * @return 任务状态
     */
    Mono<PollingTaskStatusDto> getTaskStatus(String taskId);

    /**
     * 长轮询获取任务状态
     * 如果任务状态未变化，会等待直到状态变化或超时
     *
     * @param taskId 任务ID
     * @param lastVersion 上次已知的版本号
     * @param timeout 最大等待时间
     * @return 任务状态
     */
    Mono<PollingTaskStatusDto> longPollTaskStatus(String taskId, String lastVersion, Duration timeout);

    /**
     * 取消任务
     *
     * @param taskId 任务ID
     * @return 是否成功取消
     */
    Mono<Boolean> cancelTask(String taskId);

    /**
     * 检查任务是否存在
     *
     * @param taskId 任务ID
     * @return 是否存在
     */
    Mono<Boolean> taskExists(String taskId);

    /**
     * 清理已完成的任务（可选，用于资源清理）
     *
     * @param taskId 任务ID
     * @return 是否成功清理
     */
    Mono<Boolean> cleanupTask(String taskId);
}
