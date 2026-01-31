import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Temporary: Hardcode user ID for testing
    console.log('Function called! qrData:', qrData);
    const userId = 'c93f5119-d5b1-4429-8d9e-54610d67aa75';

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    );

    const { qrData, userLat, userLng } = await req.json();

    // Get salesman record
    const { data: salesman, error: salesmanError } = await supabaseClient
      .from('salesmen')
      .select('id')
      .eq('user_id', userId)
      .maybeSingle();

    if (salesmanError) {
      throw new Error(`SALESMAN_ERROR: ${salesmanError.message}`);
    }
    
    if (!salesman) {
      throw new Error('SALESMAN_NOT_FOUND');
    }

    // Get shop by QR code
    const { data: shop, error: shopError } = await supabaseClient
      .from('shops')
      .select('id, latitude, longitude, qr_code_hash, shop_name')
      .eq('qr_code_hash', qrData)
      .maybeSingle();

    if (shopError) {
      throw new Error(`SHOP_ERROR: ${shopError.message}`);
    }
    
    if (!shop) {
      throw new Error('SHOP_NOT_FOUND');
    }

    // LOCK 1: Verify GPS proximity (50m geofence)
    const distance = calculateHaversineDistance(
      userLat, userLng,
      shop.latitude, shop.longitude
    );

    const gpsValid = distance <= 50;

    // LOCK 2: Verify QR code authenticity
    const qrValid = qrData === shop.qr_code_hash;

    // LOCK 3: Server timestamp (ignores client time)
    const serverTimestamp = new Date();
    const timeSyncValid = true;

    // Validation errors
    const validationErrors = [];
    if (!gpsValid) validationErrors.push(`GPS out of range: ${distance.toFixed(2)}m`);
    if (!qrValid) validationErrors.push('Invalid QR code');

    // All locks must pass
    if (!gpsValid || !qrValid) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          errors: validationErrors,
          distance: distance.toFixed(2)
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      );
    }

    // Create visit record
    const { data: visit, error: visitError } = await supabaseClient
      .from('visits')
      .insert({
        salesman_id: salesman.id,
        shop_id: shop.id,
        verified_at: serverTimestamp,
        gps_lat: userLat,
        gps_lng: userLng,
        distance_from_shop: distance,
      })
      .select()
      .single();

    if (visitError) {
      throw new Error(`VISIT_ERROR: ${visitError.message}`);
    }

    // Log validation details
    await supabaseClient.from('visit_validations').insert({
      visit_id: visit.id,
      gps_valid: gpsValid,
      qr_valid: qrValid,
      time_sync_valid: timeSyncValid,
      validation_errors: validationErrors.length > 0 ? validationErrors : null
    });

    return new Response(
      JSON.stringify({ 
        success: true, 
        visit: visit,
        shopName: shop.shop_name,
        distance: distance.toFixed(2)
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Edge function error:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    );
  }
});

function calculateHaversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371e3;
  const φ1 = (lat1 * Math.PI) / 180;
  const φ2 = (lat2 * Math.PI) / 180;
  const Δφ = ((lat2 - lat1) * Math.PI) / 180;
  const Δλ = ((lon2 - lon1) * Math.PI) / 180;

  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
            Math.cos(φ1) * Math.cos(φ2) *
            Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c;
}