import { createSmsHandler } from './service.ts';

Deno.serve(createSmsHandler({
  enabled: Deno.env.get('MSG91_SMS_ENABLED') === 'true',
  hookSecret: Deno.env.get('SEND_SMS_HOOK_SECRET') ?? '',
  msg91AuthKey: Deno.env.get('MSG91_AUTH_KEY') ?? '',
  templateId: Deno.env.get('MSG91_TEMPLATE_ID') ?? '',
  otpVariable: Deno.env.get('MSG91_OTP_VARIABLE') ?? 'VAR1',
  supabaseUrl: Deno.env.get('SUPABASE_URL') ?? '',
  serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
}));
