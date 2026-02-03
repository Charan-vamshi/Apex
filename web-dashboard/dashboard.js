const SUPABASE_URL = 'https://odnfdlybycecqmlkzlmy.supabase.co';
const SUPABASE_KEY = 'sb_publishable_JYAGEwycAAFeK5aSL-zrlg_HJlOj-7R';
const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

let allVisits = [];
let chart = null;

async function loadSalesmenAndShops() {
    const { data: salesmen } = await supabase
        .from('salesmen')
        .select('id, employee_code, users(full_name)');
    
    const { data: shops } = await supabase
        .from('shops')
        .select('id, shop_name');
    
    const salesmenSelect = document.getElementById('filterSalesman');
    salesmen?.forEach(s => {
        const option = document.createElement('option');
        option.value = s.id;
        option.textContent = s.users?.full_name || s.employee_code;
        salesmenSelect.appendChild(option);
    });

    const shopsSelect = document.getElementById('filterShop');
    shops?.forEach(sh => {
        const option = document.createElement('option');
        option.value = sh.id;
        option.textContent = sh.shop_name;
        shopsSelect.appendChild(option);
    });
}

async function loadDashboard() {
    try {
        const filterDate = document.getElementById('filterDate').value;
        const filterSalesman = document.getElementById('filterSalesman').value;
        const filterShop = document.getElementById('filterShop').value;
        
        let query = supabase
            .from('visits')
            .select(`
                *,
                shops(shop_name, address),
                salesmen(employee_code, users(full_name, email))
            `)
            .order('verified_at', { ascending: false });
        
        if (filterDate) {
            query = query.gte('verified_at', filterDate + 'T00:00:00')
                        .lte('verified_at', filterDate + 'T23:59:59');
        }
        if (filterSalesman) {
            query = query.eq('salesman_id', filterSalesman);
        }
        if (filterShop) {
            query = query.eq('shop_id', filterShop);
        }
        
        const { data: visits, error } = await query.limit(100);
        if (error) throw error;
        
        allVisits = visits;

        // Calculate stats
        const today = new Date().toISOString().split('T')[0];
        const todayVisits = visits.filter(v => v.verified_at.startsWith(today));
        const anomalies = visits.filter(v => v.distance_from_shop > 50);
        
        document.getElementById('totalVisits').textContent = todayVisits.length;
        document.getElementById('activeSalesmen').textContent = new Set(visits.map(v => v.salesman_id)).size;
        document.getElementById('shopsCovered').textContent = new Set(visits.map(v => v.shop_id)).size;
        document.getElementById('anomalies').textContent = anomalies.length;

        renderChart(visits);
        renderVisits(visits);
    } catch (error) {
        console.error('Error:', error);
        document.getElementById('visitsList').innerHTML = `<p class="loading">Error: ${error.message}</p>`;
    }
}

function renderChart(visits) {
    const last7Days = [...Array(7)].map((_, i) => {
        const d = new Date();
        d.setDate(d.getDate() - (6 - i));
        return d.toISOString().split('T')[0];
    });

    const visitCounts = last7Days.map(date => 
        visits.filter(v => v.verified_at.startsWith(date)).length
    );

    const ctx = document.getElementById('visitsChart');
    if (chart) chart.destroy();
    
    chart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: last7Days.map(d => new Date(d).toLocaleDateString()),
            datasets: [{
                label: 'Visits',
                data: visitCounts,
                borderColor: '#2196F3',
                backgroundColor: 'rgba(33, 150, 243, 0.1)',
                tension: 0.4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { display: false }
            }
        }
    });
}

function renderVisits(visits) {
    const visitsList = document.getElementById('visitsList');
    
    if (visits.length === 0) {
        visitsList.innerHTML = '<p class="loading">No visits found</p>';
        return;
    }

    visitsList.innerHTML = visits.map(v => `
        <div class="visit-card">
            ${v.photo_url ? `<img src="${v.photo_url}" class="visit-photo" onerror="this.style.display='none'" alt="Visit photo">` : ''}
            <div class="visit-info">
                <h4>${v.shops?.shop_name || 'Unknown'}</h4>
                <p><strong>Salesman:</strong> ${v.salesmen?.users?.full_name || v.salesmen?.employee_code}</p>
                <p><strong>Time:</strong> ${new Date(v.verified_at).toLocaleString()}</p>
                <p><strong>Distance:</strong> ${v.distance_from_shop?.toFixed(1)}m 
                    <span class="badge ${v.distance_from_shop <= 50 ? 'badge-success' : 'badge-danger'}">
                        ${v.distance_from_shop <= 50 ? 'Valid' : 'ANOMALY'}
                    </span>
                </p>
                <p><strong>GPS:</strong> ${v.gps_lat.toFixed(6)}, ${v.gps_lng.toFixed(6)}</p>
            </div>
        </div>
    `).join('');
}

function resetFilters() {
    document.getElementById('filterDate').value = '';
    document.getElementById('filterSalesman').value = '';
    document.getElementById('filterShop').value = '';
    loadDashboard();
}

function exportToCSV() {
    const headers = ['Date', 'Time', 'Salesman', 'Shop', 'Distance(m)', 'GPS Lat', 'GPS Lng', 'Status'];
    const rows = allVisits.map(v => [
        new Date(v.verified_at).toLocaleDateString(),
        new Date(v.verified_at).toLocaleTimeString(),
        v.salesmen?.users?.full_name || v.salesmen?.employee_code,
        v.shops?.shop_name,
        v.distance_from_shop?.toFixed(1),
        v.gps_lat,
        v.gps_lng,
        v.distance_from_shop <= 50 ? 'Valid' : 'Anomaly'
    ]);

    const csv = [headers, ...rows].map(row => row.join(',')).join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `apex-visits-${new Date().toISOString().split('T')[0]}.csv`;
    a.click();
}

// Initialize
loadSalesmenAndShops();
loadDashboard();
setInterval(loadDashboard, 30000);