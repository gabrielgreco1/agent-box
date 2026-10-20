# Timeline: example-com

```
05:56:33.675  HTTP    ERR GET egress direct http://clients2.google.com/time/1/current?cup2key=[redacted]&cup2hreq=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 error=blocked: noise BLOCKED=noise
05:56:33.693  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
05:56:33.698  HTTP    ERR CONNECT egress direct update.googleapis.com:443 error=blocked: noise BLOCKED=noise
05:56:34.669  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
05:56:37.550  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
05:56:41.350  PLAN    Open example.com, read the actual document title, and submit with request-log evidence.
05:56:42.958  DOING   Navigating the isolated browser to https://example.com.
05:56:43.337  HTTP    200 GET browser direct https://example.com/
05:56:43.404  HTTP    200 GET browser direct https://example.com/s.js
05:56:43.767  HTTP    ERR CONNECT egress direct www.google.com:443
05:56:46.324  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
05:56:49.403  FOUND   Opened https://example.com/; browser reported title Example Domain and HTTP status 200.  [evidence: 01M5BY4BDZ572G9E71TR8T5ZW4]
05:56:49.541  NOTE    result submitted: 2 verified, 0 cited_missing, 0 not_verified
```
