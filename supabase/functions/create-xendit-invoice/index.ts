// Supabase Edge Function: create-xendit-invoice
// Called by the app at checkout (online payment). Creates a Xendit invoice
// (GCash, Maya, cards, bank...) for an existing order and returns its URL.
//
// Secrets (never in the app):
//   supabase secrets set XENDIT_SECRET_KEY=xnd_development_...
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided
// automatically by Supabase.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const xenditKey = Deno.env.get('XENDIT_SECRET_KEY');
    if (!xenditKey) return json({ error: 'Xendit is not configured.' }, 500);

    // Who is calling? (the logged-in app user)
    const authHeader = req.headers.get('Authorization') ?? '';
    const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) return json({ error: 'Not logged in.' }, 401);
    const user = userData.user;

    const { orderId } = await req.json();
    if (!orderId || typeof orderId !== 'string') {
      return json({ error: 'orderId is required.' }, 400);
    }

    // Load the order with the service role (bypasses Row Level Security).
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: order, error: orderErr } = await admin
      .from('orders')
      .select('*')
      .eq('id', orderId)
      .single();
    if (orderErr || !order) return json({ error: 'Order not found.' }, 404);

    // Only the owner can pay, and only for an unpaid online order.
    if (order.user_id !== user.id) return json({ error: 'Not your order.' }, 403);
    if (order.payment_method !== 'xendit' || order.status !== 'awaiting_payment') {
      return json({ error: 'This order cannot be paid online.' }, 400);
    }

    // Reuse the invoice if one was already created for this order.
    if (order.xendit_invoice_url) {
      return json({ invoiceUrl: order.xendit_invoice_url });
    }

    const res = await fetch('https://api.xendit.co/v2/invoices', {
      method: 'POST',
      headers: {
        Authorization: 'Basic ' + btoa(xenditKey + ':'),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        external_id: order.id, // the webhook uses this to find the order
        amount: Number(order.total_price), // the price the SERVER calculated
        currency: 'PHP',
        description: `Jugan Gym order ${order.id}`,
        payer_email: user.email,
        customer: {
          given_names: order.customer_name,
          email: user.email,
          mobile_number: order.phone,
        },
        invoice_duration: 3600, // link expires in 1 hour
        items: (order.items as any[]).map((i) => ({
          name: i.name,
          quantity: i.qty,
          price: Number(i.unitPrice),
        })),
      }),
    });

    const invoice = await res.json();
    if (!res.ok) {
      console.error('Xendit error', res.status, JSON.stringify(invoice));
      return json({ error: 'Xendit could not create the invoice.' }, 502);
    }

    await admin
      .from('orders')
      .update({
        xendit_invoice_id: invoice.id,
        xendit_invoice_url: invoice.invoice_url,
      })
      .eq('id', order.id);

    return json({ invoiceUrl: invoice.invoice_url });
  } catch (e) {
    console.error(e);
    return json({ error: 'Something went wrong.' }, 500);
  }
});
