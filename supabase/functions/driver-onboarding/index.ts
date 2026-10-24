import { createHandler } from './service.ts';

Deno.serve(createHandler({
  supabaseUrl: Deno.env.get('SUPABASE_URL') ?? '',
  serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  digiLocker: {
    clientId: Deno.env.get('DIGILOCKER_CLIENT_ID') ?? '',
    clientSecret: Deno.env.get('DIGILOCKER_CLIENT_SECRET') ?? '',
    redirectUri: Deno.env.get('DIGILOCKER_REDIRECT_URI') ?? '',
    authorizationUrl: Deno.env.get('DIGILOCKER_AUTHORIZATION_URL') ?? '',
    tokenUrl: Deno.env.get('DIGILOCKER_TOKEN_URL') ?? '',
    issuedDocumentsUrl: Deno.env.get('DIGILOCKER_ISSUED_DOCUMENTS_URL') ?? '',
    documentUrlTemplate: Deno.env.get('DIGILOCKER_DOCUMENT_URL_TEMPLATE') ?? '',
    scope: Deno.env.get('DIGILOCKER_SCOPE') ?? '',
  },
}));
