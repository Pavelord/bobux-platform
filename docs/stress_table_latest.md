# Stress Harness Report

Generated: 2026-04-11 00:47:03

| Scenario | Status | Duration(s) | Peak CPU(%) | Peak RAM(MB) | Errors | Warnings | Parse | HostTimeout | NullPeer | PollSpam | Timeout | Log |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Static checks | PASS | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | False | non_ascii=0; while_true=0; instantiate_in_frame=0 |
| Boot Login | PASS | 8.81 | 0.49 | 8.02 | 0 | 1 | 0 | 0 | 0 | 0 | False | C:\robloxclone\stress_reports\20260411_004600\logs\boot_login.log |
| Boot Lobby | PASS | 9.77 | 0.49 | 8.02 | 0 | 1 | 0 | 0 | 0 | 0 | False | C:\robloxclone\stress_reports\20260411_004600\logs\boot_lobby.log |
| Boot Main | PASS | 7.96 | 0 | 8.02 | 0 | 1 | 0 | 0 | 0 | 0 | False | C:\robloxclone\stress_reports\20260411_004600\logs\boot_main.log |
| Lobby Loop #1 | PASS | 9.75 | 0.49 | 8.02 | 0 | 1 | 0 | 0 | 0 | 0 | False | C:\robloxclone\stress_reports\20260411_004600\logs\lobby_loop_1.log |
| Lobby Loop #2 | PASS | 8.68 | 0.49 | 8.02 | 0 | 1 | 0 | 0 | 0 | 0 | False | C:\robloxclone\stress_reports\20260411_004600\logs\lobby_loop_2.log |
| Lobby Loop #3 | PASS | 8.97 | 0.5 | 8.02 | 0 | 1 | 0 | 0 | 0 | 0 | False | C:\robloxclone\stress_reports\20260411_004600\logs\lobby_loop_3.log |
| Parallel Lobby x2 | PASS | 9.29 | 0 | 16.04 | 0 | 2 | 0 | 0 | 0 | 0 | False | C:\robloxclone\stress_reports\20260411_004600\logs\parallel_lobby_2x.log |

Summary: fail=0 warn=0 total=8

Notes:
- Headless quit-after runs may report ObjectDB leaks because the engine is forced to exit while async requests are still in flight.
- FAIL is only used for parse/runtime hard errors, explicit timeouts, or non-zero ERROR signatures.

