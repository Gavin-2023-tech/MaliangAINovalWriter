package com.ainovel.server.web.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 长轮询请求DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
public class LongPollingRequest {
    /**
     * 任务ID
     */
    private String taskId;

    /**
     * 最大等待时间（秒），默认30秒
     */
    @Builder.Default
    private Integer timeoutSeconds = 30;

    /**
     * 上次已知的状态版本号，用于检测状态是否变化
     */
    private String lastVersion;

    /**
     * 是否只在状态变化时返回
     */
    @Builder.Default
    private Boolean onlyOnChange = true;
}
