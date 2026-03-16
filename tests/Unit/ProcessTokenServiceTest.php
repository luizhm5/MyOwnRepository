<?php

namespace Tests\Unit;

use App\Services\ProcessTokenService;
use Tests\TestCase;

class ProcessTokenServiceTest extends TestCase
{
    /**
     * Test that a generated token validates successfully.
     */
    public function test_generate_and_validate_round_trip(): void
    {
        $taskId = 123;
        $userId = '005Hr00000ICGXkIAP';
        $application = 'pfx_export';

        $token = ProcessTokenService::generate($taskId, $userId, $application);

        $result = ProcessTokenService::validate($token, $taskId);

        $this->assertTrue($result['valid']);
        $this->assertEquals($taskId, $result['taskId']);
        $this->assertEquals($userId, $result['userId']);
        $this->assertEquals($application, $result['app']);
    }

    /**
     * Test that an invalid token format is rejected.
     */
    public function test_invalid_token_format_rejected(): void
    {
        $result = ProcessTokenService::validate('invalid_token_no_dot', 123);

        $this->assertFalse($result['valid']);
        $this->assertEquals('Invalid token format', $result['error']);
    }

    /**
     * Test that a completely garbage token is rejected.
     */
    public function test_garbage_token_rejected(): void
    {
        $result = ProcessTokenService::validate('abc.def', 123);

        $this->assertFalse($result['valid']);
        $this->assertEquals('Invalid token signature', $result['error']);
    }

    /**
     * Test that a tampered payload is rejected (signature mismatch).
     */
    public function test_tampered_payload_rejected(): void
    {
        $token = ProcessTokenService::generate(123, 'user123', 'pfx_export');

        // Tamper with the payload portion (before the dot)
        $parts = explode('.', $token);
        $parts[0] = $parts[0] . 'TAMPERED';
        $tamperedToken = implode('.', $parts);

        $result = ProcessTokenService::validate($tamperedToken, 123);

        $this->assertFalse($result['valid']);
        $this->assertContains($result['error'], ['Invalid token signature', 'Invalid token payload']);
    }

    /**
     * Test that a token for a different taskId is rejected.
     */
    public function test_wrong_task_id_rejected(): void
    {
        $token = ProcessTokenService::generate(123, 'user123', 'pfx_export');

        $result = ProcessTokenService::validate($token, 456);

        $this->assertFalse($result['valid']);
        $this->assertEquals('Token taskId mismatch', $result['error']);
    }

    /**
     * Test that an empty token is rejected.
     */
    public function test_empty_token_rejected(): void
    {
        $result = ProcessTokenService::validate('', 123);

        $this->assertFalse($result['valid']);
    }

    /**
     * Test that the token is URL-safe (no +, /, or = characters in payload portion).
     */
    public function test_token_is_url_safe(): void
    {
        // Generate multiple tokens to increase chance of hitting problematic base64 chars
        for ($i = 0; $i < 20; $i++) {
            $token = ProcessTokenService::generate($i, "user_with_special_chars_{$i}", 'invoice_export');
            $payloadPart = explode('.', $token)[0];

            $this->assertStringNotContainsString('+', $payloadPart, "Token payload contains + character");
            $this->assertStringNotContainsString('/', $payloadPart, "Token payload contains / character");
            $this->assertStringNotContainsString('=', $payloadPart, "Token payload contains = character");
        }
    }

    /**
     * Test that different applications produce valid tokens.
     */
    public function test_different_applications(): void
    {
        $apps = ['invoice_export', 'history_export', 'pfx_export'];

        foreach ($apps as $app) {
            $token = ProcessTokenService::generate(100, 'testuser', $app);
            $result = ProcessTokenService::validate($token, 100);

            $this->assertTrue($result['valid'], "Token validation failed for app: {$app}");
            $this->assertEquals($app, $result['app']);
        }
    }

    /**
     * Test that a tampered signature is rejected.
     */
    public function test_tampered_signature_rejected(): void
    {
        $token = ProcessTokenService::generate(123, 'user123', 'pfx_export');

        // Tamper with the signature portion (after the dot)
        $parts = explode('.', $token);
        $parts[1] = str_repeat('a', 64); // Replace with fake signature
        $tamperedToken = implode('.', $parts);

        $result = ProcessTokenService::validate($tamperedToken, 123);

        $this->assertFalse($result['valid']);
        $this->assertEquals('Invalid token signature', $result['error']);
    }
}
