// SPDX-License-Identifier: Apache-2.0
//
// Load test of the dev environment, run by `make test-load` (tools/load-test.sh).
// Open model: requests start at the configured rate whatever the response
// times, so saturation shows up as latency, errors and dropped iterations.
//
// Environment:
//   TARGET_IP      address of the kind node with the controller (required)
//   LOAD_SCENARIO  steady | limit | reload | soak | default-backend
//   PROTOCOL       http | https
//   RATE           requests per second (limit: the final rate)
//   DURATION       duration of the scenario (limit: of the ramp)
//   BODY_SIZE      bytes of a POST body; 0 sends GET
//   REUSE          false opens a new connection for every request
//   P95_MS, P99_MS latency thresholds
//   MAX_VUS        upper bound of concurrent requests

import exec from 'k6/execution';
import http from 'k6/http';
import { check } from 'k6';

const env = (name, fallback) => __ENV[name] || fallback;

const targetIP = __ENV.TARGET_IP;
if (!targetIP) {
  throw new Error('TARGET_IP is not set; run the test with make test-load');
}

const scenarioName = env('LOAD_SCENARIO', 'steady');
const scheme = env('PROTOCOL', 'http') === 'https' ? 'https' : 'http';
const rate = parseInt(env('RATE', '500'), 10);
const duration = env('DURATION', '1m');
const bodySize = parseInt(env('BODY_SIZE', '0'), 10);
const reuse = env('REUSE', 'true') !== 'false';
const p95 = parseInt(env('P95_MS', '500'), 10);
const p99 = parseInt(env('P99_MS', '1500'), 10);
const maxVUs = parseInt(env('MAX_VUS', '2000'), 10);
const preAllocatedVUs = Math.min(Math.max(rate, 10), maxVUs);

const constantRate = (execName) => ({
  executor: 'constant-arrival-rate',
  exec: execName,
  rate,
  timeUnit: '1s',
  duration,
  preAllocatedVUs,
  maxVUs,
});

const scenarios = {
  steady: constantRate('echo'),
  reload: constantRate('echo'),
  soak: constantRate('echo'),
  'default-backend': constantRate('defaultBackend'),
  limit: {
    executor: 'ramping-arrival-rate',
    exec: 'echo',
    startRate: Math.max(Math.floor(rate / 20), 1),
    timeUnit: '1s',
    stages: [{ target: rate, duration }],
    preAllocatedVUs,
    maxVUs,
  },
};

if (!scenarios[scenarioName]) {
  throw new Error(`unknown LOAD_SCENARIO ${scenarioName}: use ${Object.keys(scenarios).join(', ')}`);
}

// Configuration changes run while the scenarios reload and soak are measured,
// so they allow fewer failed requests.
const maxFailed = ['reload', 'soak'].includes(scenarioName) ? 0.001 : 0.01;

// limit stops at the first sustained violation: the request rate reached until
// then is the capacity of this setup.
const limit = scenarioName === 'limit';
const threshold = (expression) =>
  limit ? { threshold: expression, abortOnFail: true, delayAbortEval: '10s' } : expression;

const thresholds = {
  http_req_failed: [threshold(`rate<${maxFailed}`)],
  http_req_duration: [threshold(`p(95)<${p95}`), threshold(`p(99)<${p99}`)],
  checks: ['rate>0.99'],
};
if (!limit) {
  // A dropped iteration is a request that could not start in time: the
  // configured rate was not reached.
  thresholds.dropped_iterations = ['count==0'];
}

export const options = {
  scenarios: { [scenarioName]: scenarios[scenarioName] },
  thresholds,
  hosts: {
    'load.local': targetIP,
    'errors.load.local': targetIP,
    'unknown.load.local': targetIP,
  },
  insecureSkipTLSVerify: true,
  noConnectionReuse: !reuse,
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const body = bodySize > 0 ? 'x'.repeat(bodySize) : null;

// Traffic through the controller to the echo backend.
export function echo() {
  const url = `${scheme}://load.local/load`;
  const res = body
    ? http.post(url, body, { headers: { 'Content-Type': 'application/octet-stream' } })
    : http.get(url);
  check(res, { 'status is 200': (r) => r.status === 200 });
}

// Responses of the default backend (custom-error-pages): an unknown host, and
// errors of a backend that the controller intercepts (custom-http-errors).
const defaultBackendCases = [
  { name: 'unknown host', url: `${scheme}://unknown.load.local/`, status: 404, page: 'could not be found' },
  { name: 'intercepted 404', url: `${scheme}://errors.load.local/status/404`, status: 404, page: 'could not be found' },
  { name: 'intercepted 503', url: `${scheme}://errors.load.local/status/503`, status: 503, page: '5xx html' },
];

export function defaultBackend() {
  const c = defaultBackendCases[exec.scenario.iterationInTest % defaultBackendCases.length];
  const res = http.get(c.url, {
    headers: { Accept: 'text/html' },
    responseType: 'text',
    responseCallback: http.expectedStatuses(c.status),
    tags: { case: c.name },
  });
  check(res, {
    [`${c.name}: status ${c.status}`]: (r) => r.status === c.status,
    [`${c.name}: page of the default backend`]: (r) => typeof r.body === 'string' && r.body.includes(c.page),
  });
}
