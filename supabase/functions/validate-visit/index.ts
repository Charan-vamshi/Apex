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
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    );

    const { salesmanId, shopId, qrData, userLat, userLng, photoUrl, deviceId, appVersion } = await req.json();

    // LOCK 1: Verify GPS proximity (50m geofence)
    const { data: shop, error: shopError } = await supabaseClient
      .from('shops')
      .select('latitude, longitude, qr_code_hash, shop_name')
      .eq('id', shopId)
      .single();

    if (shopError || !shop) {
      throw new Error('SHOP_NOT_FOUND');
    }

    const distance = calculateHaversineDistance(
      userLat, userLng,
      shop.latitude, shop.longitude
    );

    const gpsValid = distance <= 50;

    // LOCK 2: Verify QR code authenticity
    const qrValid = qrData === shop.qr_code_hash;

    // LOCK 3: Server timestamp (ignores client time)
    const serverTimestamp = new Date();
    const timeSyncValid = true; // Always true since server generates it

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
        salesman_id: salesmanId,
        shop_id: shopId,
        verified_at: serverTimestamp,
        gps_lat: userLat,
        gps_lng: userLng,
        distance_from_shop: distance,
        photo_url: photoUrl,
        device_id: deviceId,
        app_version: appVersion
      })
      .select()
      .single();

    if (visitError) throw visitError;

    // Log validation details
    await supabaseClient.from('visit_validations').insert({
      visit_id: visit.id,
      gps_valid: gpsValid,
      qr_valid: qrValid,
      time_sync_valid: timeSyncValid,
      validation_errors: validationErrors.length > 0 ? validationErrors : null
    });

    // Check for anomalies (simple example: multiple visits to same shop in short time)
    const { data: recentVisits } = await supabaseClient
      .from('visits')
      .select('verified_at')
      .eq('salesman_id', salesmanId)
      .eq('shop_id', shopId)
      .gte('verified_at', new Date(Date.now() - 3600000).toISOString()) // Last 1 hour
      .order('verified_at', { ascending: false })
      .limit(2);

    if (recentVisits && recentVisits.length > 1) {
      await supabaseClient.from('anomaly_flags').insert({
        visit_id: visit.id,
        flag_type: 'duplicate_visit_short_interval',
        severity: 'medium'
      });
    }

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
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    );
  }
});

// Haversine formula to calculate distance between two GPS coordinates
function calculateHaversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371e3; // Earth radius in meters
  const φ1 = (lat1 * Math.PI) / 180;
  const φ2 = (lat2 * Math.PI) / 180;
  const Δφ = ((lat2 - lat1) * Math.PI) / 180;
  const Δλ = ((lon2 - lon1) * Math.PI) / 180;

  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
            Math.cos(φ1) * Math.cos(φ2) *
            Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c; // Distance in meters
}