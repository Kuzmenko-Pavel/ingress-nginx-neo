# GeoIP2 test database

`GeoLite2-Country-Test.mmdb` is the fake test database
[`test-data/GeoLite2-Country-Test.mmdb`](https://github.com/maxmind/MaxMind-DB/blob/5a0be1c0320490b8e4379dbd5295a18a648ff156/test-data/GeoLite2-Country-Test.mmdb)
of [maxmind/MaxMind-DB](https://github.com/maxmind/MaxMind-DB) at commit `5a0be1c0`, licensed under
Apache-2.0 or MIT. It contains no real GeoIP data.

The e2e image carries it at `/GeoLite2-Country-Test.mmdb`, so the Geoip2 tests need no network access.
