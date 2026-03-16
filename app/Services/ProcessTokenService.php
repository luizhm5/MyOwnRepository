<?php

namespace App\Services;

class ProcessTokenService
{
    private const TOKEN_VALIDITY_HOURS = 5;

    /**
     * Generate a secure token for process endpoint access
     *
     * @param int $taskId - Task ID from database
     * @param string $userId - Salesforce user ID
     * @param string $application - App type (pfx_export, history_export, invoice_export)
     * @return string - Signed token
     */
    public static function generate(int $taskId, string $userId, string $application): string
    {
        $expiresAt = time() + (self::TOKEN_VALIDITY_HOURS * 3600);

        // Payload: taskId:userId:app:expiresAt
        $payload = "{$taskId}:{$userId}:{$application}:{$expiresAt}";

        // Sign with app key
        $signature = hash_hmac('sha256', $payload, config('app.key'));

        // Return: base64url(payload).signature
        return self::base64urlEncode($payload) . '.' . $signature;
    }

    /**
     * Validate token and extract data
     *
     * @param string $token - Token from query parameter
     * @param int $expectedTaskId - TaskId to validate against
     * @return array - ['valid' => bool, 'taskId' => int, 'userId' => string, 'app' => string, 'error' => string]
     */
    public static function validate(string $token, int $expectedTaskId): array
    {
        $parts = explode('.', $token);

        if (count($parts) !== 2) {
            return ['valid' => false, 'error' => 'Invalid token format'];
        }

        [$payloadEncoded, $signature] = $parts;

        // Decode payload
        $payload = self::base64urlDecode($payloadEncoded);
        if ($payload === false) {
            return ['valid' => false, 'error' => 'Invalid token encoding'];
        }

        // Verify signature
        $expectedSignature = hash_hmac('sha256', $payload, config('app.key'));
        if (!hash_equals($expectedSignature, $signature)) {
            return ['valid' => false, 'error' => 'Invalid token signature'];
        }

        // Parse payload
        $payloadParts = explode(':', $payload);
        if (count($payloadParts) !== 4) {
            return ['valid' => false, 'error' => 'Invalid token payload'];
        }

        [$taskId, $userId, $application, $expiresAt] = $payloadParts;

        // Verify not expired
        if (time() > (int)$expiresAt) {
            return ['valid' => false, 'error' => 'Token expired'];
        }

        // Verify taskId matches
        if ((int)$taskId !== $expectedTaskId) {
            return ['valid' => false, 'error' => 'Token taskId mismatch'];
        }

        return [
            'valid' => true,
            'taskId' => (int)$taskId,
            'userId' => $userId,
            'app' => $application
        ];
    }

    /**
     * URL-safe base64 encode (replaces +/ with -_ and strips padding)
     */
    private static function base64urlEncode(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    /**
     * URL-safe base64 decode
     */
    private static function base64urlDecode(string $data): string|false
    {
        return base64_decode(strtr($data, '-_', '+/'));
    }
}
