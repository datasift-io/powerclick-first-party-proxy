___TERMS_OF_SERVICE___

By creating or modifying this file you agree to Google Tag Manager's Community
Template Gallery Developer Terms of Service available at
https://developers.google.com/tag-manager/gallery-tos (or such other URL as
Google may provide), as modified from time to time.



___INFO___

{
  "type": "CLIENT",
  "id": "cvt_temp_public_id",
  "version": 1,
  "securityGroups": [],
  "displayName": "PowerClick First-Party Proxy",
  "categories": [
    "ATTRIBUTION",
    "UTILITY"
  ],
  "brand": {
    "id": "brand_dummy",
    "displayName": "PowerClick"
  },
  "description": "Serves the PowerClick loader and its event posts from this server container's own domain, so ad blockers that block PowerClick's domains don't block PowerClick on your site.",
  "containerContexts": [
    "SERVER"
  ]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "TEXT",
    "name": "tenantId",
    "displayName": "PowerClick Account ID",
    "simpleValueType": true,
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      },
      {
        "type": "REGEX",
        "args": [
          "^[A-Za-z0-9_-]{1,100}$"
        ]
      }
    ],
    "help": "Your PowerClick Account ID \u2014 the same one as in the web PowerClick tag."
  },
  {
    "type": "TEXT",
    "name": "scriptPath",
    "displayName": "Script path",
    "simpleValueType": true,
    "defaultValue": "/c/l.js",
    "valueValidators": [
      {
        "type": "REGEX",
        "args": [
          "^/[A-Za-z0-9._~/-]{1,100}$"
        ]
      }
    ],
    "help": "Path the loader script is served on. The web PowerClick tag's First-party script URL is https://&lt;this container's domain&gt;&lt;this path&gt;. Any neutral path works; avoid words like <i>track</i>, <i>pixel</i> or <i>powerclick</i>, which ad blockers match."
  },
  {
    "type": "TEXT",
    "name": "ingestPath",
    "displayName": "Event path",
    "simpleValueType": true,
    "defaultValue": "/c/e",
    "valueValidators": [
      {
        "type": "REGEX",
        "args": [
          "^/[A-Za-z0-9._~/-]{1,100}$"
        ]
      }
    ],
    "help": "Path the loader posts its events to. Set automatically in the loader; nothing else to change."
  }
]


___SANDBOXED_JS_FOR_SERVER___

// PowerClick First-Party Proxy — sGTM CLIENT template.
//
// SETUP: import gtm-scripts/sgtm/powerclick-proxy.tpl (sGTM → Templates → Client Templates → ⋮ → Import), never
// paste. Rebuild after editing this file: python3 gtm-scripts/sgtm/build_proxy.py
// Then Clients → New → PowerClick First-Party Proxy, enter the tenant id, save, publish. No tags or triggers.
//
// Serves the PowerClick loader and its event posts from the tenant's own sGTM host (Stape custom domain, e.g.
// ss.example.com), so ad blockers that block js.powerclick.io / ingest.powerclick.io don't see either:
//
//   GET  {scriptPath}   → https://js.powerclick.io/pc.js?id=<tenant>&fp=https://<this host>{ingestPath}
//                          fp tells the loader worker to point the loader's ingest at this host. The worker
//                          accepts it only when the host matches the tenant's configured sGTM URL.
//   POST {ingestPath}   → https://ingest.powerclick.io/api/ingest?tenant_id=<tenant>, body unchanged, with the
//                          visitor's IP / UA / Stape x-geo-* headers (otherwise ingest would record Stape's
//                          datacenter as the visitor).
//   OPTIONS {ingestPath} → CORS preflight (the engagement fallback posts application/json).
//
// The web GTM PowerClick tag loads https://<this host>{scriptPath} instead of js.powerclick.io (its
// "First-party script URL" field). Design: docs/POWERCLICK_LOADER.md §27.

const claimRequest = require('claimRequest');
const encodeUriComponent = require('encodeUriComponent');
const getRemoteAddress = require('getRemoteAddress');
const getRequestBody = require('getRequestBody');
const getRequestHeader = require('getRequestHeader');
const getRequestMethod = require('getRequestMethod');
const getRequestPath = require('getRequestPath');
const getTimestampMillis = require('getTimestampMillis');
const returnResponse = require('returnResponse');
const sendHttpRequest = require('sendHttpRequest');
const setResponseBody = require('setResponseBody');
const setResponseHeader = require('setResponseHeader');
const setResponseStatus = require('setResponseStatus');
const templateDataStorage = require('templateDataStorage');

const LOADER = 'https://js.powerclick.io/pc.js';
const INGEST = 'https://ingest.powerclick.io/api/ingest?tenant_id=';
const FRESH_MS = 300000;      // same as the worker's browser max-age: a loader release reaches visitors in ~5 min
const TIMEOUT_MS = 5000;
// Stape's geo headers (power-up "Geo headers"). The ingest worker reads exactly these.
const GEO_HEADERS = ['x-geo-country', 'x-geo-region', 'x-geo-city', 'x-geo-postalcode', 'x-geo-ipaddress'];

function normPath(p, dflt) {
  p = p || dflt;
  return p.charAt(0) === '/' ? p : '/' + p;
}

const tenant = data.tenantId;
const scriptPath = normPath(data.scriptPath, '/c/l.js');
const ingestPath = normPath(data.ingestPath, '/c/e');
const path = getRequestPath();

if (tenant && (path === scriptPath || path === ingestPath)) {
  claimRequest();
  const method = getRequestMethod();
  if (path === scriptPath && method === 'GET') {
    serveScript();
  } else if (path === ingestPath && method === 'OPTIONS') {
    cors();
    setResponseHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    setResponseHeader('Access-Control-Allow-Headers', 'Content-Type');
    setResponseHeader('Access-Control-Max-Age', '86400');
    respond(204, '');
  } else if (path === ingestPath && method === 'POST') {
    forwardIngest();
  } else {
    respond(405, '');
  }
}

function respond(status, body) {
  setResponseStatus(status);
  setResponseBody(body);
  returnResponse();
}

// Credentialed requests (sendBeacon always is) need the exact origin echoed, never '*'.
function cors() {
  const origin = getRequestHeader('origin');
  if (!origin) return;
  setResponseHeader('Access-Control-Allow-Origin', origin);
  setResponseHeader('Access-Control-Allow-Credentials', 'true');
  setResponseHeader('Vary', 'Origin');
}

function serveScript() {
  const host = getRequestHeader('host');
  const url = LOADER + '?id=' + encodeUriComponent(tenant) +
    '&fp=' + encodeUriComponent('https://' + host + ingestPath);
  const key = 'pc_loader:' + url;
  const cached = templateDataStorage.getItemCopy(key);
  const now = getTimestampMillis();

  const send = (body, source) => {
    setResponseHeader('Content-Type', 'application/javascript; charset=utf-8');
    setResponseHeader('Cache-Control', 'public, max-age=300');
    setResponseHeader('X-PowerClick-Proxy', source);
    respond(200, body);
  };
  // A cached copy is served when the loader host can't be reached: tracking keeps working through an outage.
  const fallback = () => {
    if (cached) return send(cached.body, 'stale');
    setResponseHeader('Content-Type', 'application/javascript; charset=utf-8');
    setResponseHeader('Cache-Control', 'no-store');
    respond(200, '/* PowerClick: loader unavailable, retrying on next page */');
  };

  if (cached && now - cached.at < FRESH_MS) return send(cached.body, 'cache');
  sendHttpRequest(url, { method: 'GET', timeout: TIMEOUT_MS }).then((r) => {
    if (r.statusCode !== 200 || !r.body) return fallback();
    templateDataStorage.setItemCopy(key, { body: r.body, at: now });
    send(r.body, 'origin');
  }, fallback);
}

function forwardIngest() {
  const headers = { 'Content-Type': 'text/plain' };
  const ua = getRequestHeader('user-agent');
  if (ua) headers['User-Agent'] = ua;
  GEO_HEADERS.forEach((h) => {
    const v = getRequestHeader(h);
    if (v) headers[h] = v;
  });
  // No Stape geo headers: still send the visitor's IP, which the worker prefers over its connecting peer.
  if (!headers['x-geo-ipaddress']) {
    const ip = getRemoteAddress();
    if (ip) headers['x-geo-ipaddress'] = ip;
  }
  cors();
  sendHttpRequest(INGEST + encodeUriComponent(tenant), { method: 'POST', headers: headers, timeout: TIMEOUT_MS },
                  getRequestBody() || '').then((r) => {
    respond(r.statusCode || 502, '');
  }, () => respond(502, ''));
}


___SERVER_PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "read_request",
        "versionId": "1"
      },
      "param": [
        {
          "key": "requestAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        },
        {
          "key": "headerAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        },
        {
          "key": "queryParameterAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "return_response",
        "versionId": "1"
      },
      "param": []
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "access_response",
        "versionId": "1"
      },
      "param": [
        {
          "key": "writeResponseAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        },
        {
          "key": "writeHeaderAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "send_http",
        "versionId": "1"
      },
      "param": [
        {
          "key": "allowedUrls",
          "value": {
            "type": 1,
            "string": "specific"
          }
        },
        {
          "key": "urls",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "https://js.powerclick.io/*"
              },
              {
                "type": 1,
                "string": "https://ingest.powerclick.io/*"
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "access_template_storage",
        "versionId": "1"
      },
      "param": []
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  }
]


___TESTS___

scenarios:
- name: Claims the script path and serves the loader
  code: |-
    const Promise = require('Promise');
    mock('getRequestPath', '/c/l.js');
    mock('getRequestMethod', 'GET');
    mock('getRequestHeader', (h) => h === 'host' ? 'ss.example.com' : undefined);
    mock('sendHttpRequest', (url) => {
      assertThat(url).isEqualTo('https://js.powerclick.io/pc.js?id=acme&fp=https%3A%2F%2Fss.example.com%2Fc%2Fe');
      return Promise.create((resolve) => resolve({statusCode: 200, body: '/*loader*/'}));
    });
    runCode({tenantId: 'acme', scriptPath: '/c/l.js', ingestPath: '/c/e'});
    assertApi('claimRequest').wasCalled();
- name: Answers the event-path preflight
  code: |-
    mock('getRequestPath', '/c/e');
    mock('getRequestMethod', 'OPTIONS');
    mock('getRequestHeader', (h) => h === 'origin' ? 'https://www.example.com' : undefined);
    runCode({tenantId: 'acme', scriptPath: '/c/l.js', ingestPath: '/c/e'});
    assertApi('claimRequest').wasCalled();
    assertApi('setResponseStatus').wasCalledWith(204);
    assertApi('returnResponse').wasCalled();
- name: Leaves other paths alone
  code: |-
    mock('getRequestPath', '/data');
    runCode({tenantId: 'acme', scriptPath: '/c/l.js', ingestPath: '/c/e'});
    assertApi('claimRequest').wasNotCalled();


___NOTES___

Built from gtm-scripts/sgtm/powerclick-proxy.js — do not edit in GTM; edit the .js and run gtm-scripts/sgtm/build_proxy.py.
