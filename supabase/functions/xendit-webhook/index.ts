// Supabase Edge Function: xendit-webhook
// Xendit calls this URL when an invoice is PAID or EXPIRED.
//
// Setup:
//   1. supabase secrets set XENDIT_WEBHOOK_TOKEN=<token from Xendit dashboard>
//   2. Deploy WITHOUT JWT check (Xendit has no Supabase login):
//        supabase functions deploy xendit-webhook --no-verify-jwt
//   3. Xendit Dashboard > Settings > Webhooks > Invoices paid + Invoices expired:
//        https://<project-ref>.supabase.co/functions/v1/xendit-webhook
//      (copy the "Verification token" shown there into XENDIT_WEBHOOK_TOKEN)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  // Only Xendit knows this token.
  const token = req.headers.get('x-callback-token');
  if (!token || token !== Deno.env.get('XENDIT_WEBHOOK_TOKEN')) {
    return new Response('Unauthorized', { status: 401 });
  }

  let event: any;
  try {
    event = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const orderId: string | undefined = event.external_id;
  const status: string | undefined = event.status; // PAID | SETTLED | EXPIRED
  if (!orderId || !status) return new Response('ignored', { status: 200 });

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: order } = await admin
    .from('orders')
    .select('id,status,payment_status,total_price,xendit_invoice_id')
    .eq('id', orderId)
    .maybeSingle();
  if (!order) return new Response('unknown order', { status: 200 });

  // The invoice must be the one we created for this order.
  if (order.xendit_invoice_id && event.id && order.xendit_invoice_id !== event.id) {
    return new Response('invoice mismatch', { status: 200 });
  }

  if (status === 'PAID' || status === 'SETTLED') {
    // Never trust a payment for a different amount.
    if (event.amount !== undefined && Number(event.amount) < Number(order.total_price)) {
      console.error('Amount mismatch for order', orderId, event.amount, order.total_price);
      return new Response('amount mismatch', { status: 200 });
    }
    if (order.payment_status !== 'paid') {
      await admin
        .from('orders')
        .update({
          payment_status: 'paid',
          // A cancelled order that was paid anyway stays "cancelled" so the
          // admin can see it and refund it in Xendit.
          status: order.status === 'awaiting_payment' ? 'placed' : order.status,
        })
        .eq('id', orderId);
    }
  } else if (status === 'EXPIRED') {
    // Put the items back into stock and mark the order cancelled.
    await admin.rpc('cancel_order', {
      p_order_id: orderId,
      p_payment_status: 'expired',
    });
  }

  // Always answer 200 so Xendit stops retrying.
  return new Response('ok', { status: 200 });
});
