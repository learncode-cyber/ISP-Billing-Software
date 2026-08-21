// AR Qudrix ISP OS — Load Testing Script
// Uses k6 (https://k6.io) for performance testing
// Run: k6 run scripts/load-test.js

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const TEST_DURATION = __ENV.DURATION || '5m';
const VUS = parseInt(__ENV.VUS || '100', 10); // Virtual Users
const RAMP_UP = parseInt(__ENV.RAMP_UP || '30', 10); // seconds

// Custom metrics
const errorRate = new Rate('errors');
const duration = new Trend('http_req_duration');
const apiCallCount = new Counter('api_calls');

// Test configuration
export const options = {
  stages: [
    { duration: `${RAMP_UP}s`, target: Math.floor(VUS * 0.2) }, // Ramp up to 20%
    { duration: `${RAMP_UP}s`, target: Math.floor(VUS * 0.5) }, // Ramp up to 50%
    { duration: `${RAMP_UP}s`, target: VUS }, // Ramp up to 100%
    { duration: '2m', target: VUS }, // Stay at full load for 2 minutes
    { duration: `${RAMP_UP}s`, target: Math.floor(VUS * 0.5) }, // Ramp down to 50%
    { duration: `${RAMP_UP}s`, target: 0 } // Ramp down to 0
  ],
  
  thresholds: {
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed': ['rate<0.1'],
    'errors': ['rate<0.05']
  }
};

// Setup
export function setup() {
  console.log(`Starting load test against ${BASE_URL}`);
  console.log(`VUs: ${VUS}, Duration: ${TEST_DURATION}`);
  
  // Login or get auth token
  const loginRes = http.post(`${BASE_URL}/api/auth/login`, {
    email: 'admin@test.local',
    password: 'password'
  });

  const token = loginRes.json('token');
  return { token };
}

// Main test function
export default function (data) {
  const token = data.token;
  const headers = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json'
  };

  group('Dashboard & Overview', () => {
    dashboardTest(headers);
  });

  sleep(1);

  group('Customer Management', () => {
    customerTest(headers);
  });

  sleep(1);

  group('Billing & Invoicing', () => {
    billingTest(headers);
  });

  sleep(1);

  group('Network Management', () => {
    networkTest(headers);
  });

  sleep(1);

  group('Support Tickets', () => {
    supportTest(headers);
  });

  sleep(1);

  group('Search & Filtering', () => {
    searchTest(headers);
  });
}

// Dashboard Test Scenario
function dashboardTest(headers) {
  const res = http.get(`${BASE_URL}/api/dashboards`, { headers });
  
  check(res, {
    'Dashboard status is 200': (r) => r.status === 200,
    'Dashboard response time < 500ms': (r) => r.timings.duration < 500
  }) || errorRate.add(1);

  duration.add(res.timings.duration);
  apiCallCount.add(1);
}

// Customer Management Test Scenario
function customerTest(headers) {
  // List customers
  const listRes = http.get(`${BASE_URL}/api/customers?page=1&limit=50`, { headers });
  
  check(listRes, {
    'List customers status is 200': (r) => r.status === 200,
    'List response time < 500ms': (r) => r.timings.duration < 500
  }) || errorRate.add(1);

  duration.add(listRes.timings.duration);
  apiCallCount.add(1);

  if (listRes.status === 200) {
    const customers = listRes.json('data');
    if (customers && customers.length > 0) {
      const customerId = customers[0].id;

      // Get customer details
      const detailRes = http.get(`${BASE_URL}/api/customers/${customerId}`, { headers });
      
      check(detailRes, {
        'Get customer details status is 200': (r) => r.status === 200,
        'Detail response time < 300ms': (r) => r.timings.duration < 300
      }) || errorRate.add(1);

      duration.add(detailRes.timings.duration);
      apiCallCount.add(1);

      // Update customer
      const updateRes = http.put(
        `${BASE_URL}/api/customers/${customerId}`,
        JSON.stringify({
          phone: '01712345678',
          address: 'Updated Address'
        }),
        { headers }
      );

      check(updateRes, {
        'Update customer status is 200': (r) => r.status === 200
      }) || errorRate.add(1);

      duration.add(updateRes.timings.duration);
      apiCallCount.add(1);
    }
  }
}

// Billing Test Scenario
function billingTest(headers) {
  // List invoices
  const invoiceRes = http.get(`${BASE_URL}/api/billing/invoices?page=1&limit=50`, { headers });
  
  check(invoiceRes, {
    'List invoices status is 200': (r) => r.status === 200,
    'Invoices response time < 500ms': (r) => r.timings.duration < 500
  }) || errorRate.add(1);

  duration.add(invoiceRes.timings.duration);
  apiCallCount.add(1);

  // Get billing summary
  const summaryRes = http.get(`${BASE_URL}/api/billing/summary`, { headers });
  
  check(summaryRes, {
    'Billing summary status is 200': (r) => r.status === 200
  }) || errorRate.add(1);

  duration.add(summaryRes.timings.duration);
  apiCallCount.add(1);

  // Payment records
  const paymentRes = http.get(`${BASE_URL}/api/billing/payments?page=1&limit=50`, { headers });
  
  check(paymentRes, {
    'Payment records status is 200': (r) => r.status === 200
  }) || errorRate.add(1);

  duration.add(paymentRes.timings.duration);
  apiCallCount.add(1);
}

// Network Management Test Scenario
function networkTest(headers) {
  // List devices
  const deviceRes = http.get(`${BASE_URL}/api/network/devices?page=1&limit=50`, { headers });
  
  check(deviceRes, {
    'List devices status is 200': (r) => r.status === 200,
    'Devices response time < 700ms': (r) => r.timings.duration < 700
  }) || errorRate.add(1);

  duration.add(deviceRes.timings.duration);
  apiCallCount.add(1);

  // Get device statistics
  const statsRes = http.get(`${BASE_URL}/api/network/statistics`, { headers });
  
  check(statsRes, {
    'Statistics status is 200': (r) => r.status === 200
  }) || errorRate.add(1);

  duration.add(statsRes.timings.duration);
  apiCallCount.add(1);

  // Bandwidth monitoring
  const bwRes = http.get(`${BASE_URL}/api/network/bandwidth?period=day`, { headers });
  
  check(bwRes, {
    'Bandwidth data status is 200': (r) => r.status === 200
  }) || errorRate.add(1);

  duration.add(bwRes.timings.duration);
  apiCallCount.add(1);
}

// Support Tickets Test Scenario
function supportTest(headers) {
  // List tickets
  const ticketRes = http.get(`${BASE_URL}/api/support/tickets?page=1&limit=50`, { headers });
  
  check(ticketRes, {
    'List tickets status is 200': (r) => r.status === 200,
    'Tickets response time < 500ms': (r) => r.timings.duration < 500
  }) || errorRate.add(1);

  duration.add(ticketRes.timings.duration);
  apiCallCount.add(1);

  // Create ticket
  const createRes = http.post(
    `${BASE_URL}/api/support/tickets`,
    JSON.stringify({
      subject: 'Load test ticket',
      description: 'Testing support system under load',
      priority: 'medium'
    }),
    { headers }
  );

  check(createRes, {
    'Create ticket status is 201': (r) => r.status === 201
  }) || errorRate.add(1);

  duration.add(createRes.timings.duration);
  apiCallCount.add(1);
}

// Search Test Scenario
function searchTest(headers) {
  const queries = ['customer', 'invoice', 'device', 'ticket', 'order'];
  const query = queries[Math.floor(Math.random() * queries.length)];

  const searchRes = http.get(`${BASE_URL}/api/search?q=${query}&limit=10`, { headers });
  
  check(searchRes, {
    'Search status is 200': (r) => r.status === 200,
    'Search response time < 400ms': (r) => r.timings.duration < 400
  }) || errorRate.add(1);

  duration.add(searchRes.timings.duration);
  apiCallCount.add(1);
}

// Teardown
export function teardown(data) {
  console.log('Load test completed');
}

// Logout
export function handleSummary(data) {
  console.log('\n=== LOAD TEST RESULTS ===\n');
  console.log(`Total API calls: ${apiCallCount.value}`);
  console.log(`Error rate: ${(errorRate.value * 100).toFixed(2)}%`);
  console.log(`Avg response time: ${duration.value.toFixed(2)}ms`);
  
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'summary.json': JSON.stringify(data)
  };
}

// Text summary helper
function textSummary(data, options) {
  let summary = '';
  const indent = options.indent || '';

  for (const [group, metrics] of Object.entries(data.metrics)) {
    summary += `${indent}${group}:\n`;
    for (const [metric, values] of Object.entries(metrics.values)) {
      if (typeof values === 'number') {
        summary += `${indent}  ${metric}: ${values.toFixed(2)}\n`;
      }
    }
  }

  return summary;
}
