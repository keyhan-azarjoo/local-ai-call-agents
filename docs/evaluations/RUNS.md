# Test-call runs

Every run of the spoken test calls (simulated callers speaking through text-to-speech, heard by the app's own speech recognition, answered by the AI, results checked against the business apps' data). Raw results — every conversation, tool call, timing and failure — are in [runs/](runs/). Owner details from early manual tests are masked.

| Run | Started | What | Calls | Passed | Median answer | Calls at once |
|---|---|---|---:|---:|---:|---:|
| [app-2026-10-07T01-54-45.jsonl](runs/app-2026-10-07T01-54-45.jsonl) | 2026-10-07 01:54 | Single calls | 82 | 44 (53%) | 10.6 s | 1 |
| [app-2026-10-07T02-50-10.jsonl](runs/app-2026-10-07T02-50-10.jsonl) | 2026-10-07 02:50 | Single calls | 89 | 59 (66%) | 5.8 s | 1 |
| [app-2026-10-07T03-43-57.jsonl](runs/app-2026-10-07T03-43-57.jsonl) | 2026-10-07 03:43 | Single calls | 84 | 65 (77%) | 6.2 s | 1 |
| [app-2026-10-07T04-44-28.jsonl](runs/app-2026-10-07T04-44-28.jsonl) | 2026-10-07 04:44 | Single calls | 69 | 52 (75%) | 5.7 s | 1 |
| [app-2026-10-07T05-32-04.jsonl](runs/app-2026-10-07T05-32-04.jsonl) | 2026-10-07 05:32 | Single calls | 11 | 2 (18%) | 4.9 s | 1 |
| [app-2026-10-07T05-44-24.jsonl](runs/app-2026-10-07T05-44-24.jsonl) | 2026-10-07 05:44 | Single calls | 86 | 61 (70%) | 4.7 s | 1 |
| [app-2026-10-07T06-43-15.jsonl](runs/app-2026-10-07T06-43-15.jsonl) | 2026-10-07 06:43 | Single calls | 246 | 214 (86%) | 5.5 s | 1 |
| [app-2026-10-07T09-33-04.jsonl](runs/app-2026-10-07T09-33-04.jsonl) | 2026-10-07 09:33 | Hard calls (long, tricky, other languages) | 1 | 0 (0%) | 23.5 s | 1 |
| [app-2026-10-07T09-37-39.jsonl](runs/app-2026-10-07T09-37-39.jsonl) | 2026-10-07 09:37 | Hard calls (long, tricky, other languages) | 1 | 0 (0%) | 32.0 s | 1 |
| [app-2026-10-07T09-55-13.jsonl](runs/app-2026-10-07T09-55-13.jsonl) | 2026-10-07 09:55 | Hard calls (long, tricky, other languages) | 1 | 0 (0%) | 338.4 s | 2 |
| [app-2026-10-07T10-25-29.jsonl](runs/app-2026-10-07T10-25-29.jsonl) | 2026-10-07 10:25 | Journeys (call-backs, teams, switching business) | 3 | 0 (0%) | 61.9 s | 2 |
| [app-2026-10-07T10-50-01.jsonl](runs/app-2026-10-07T10-50-01.jsonl) | 2026-10-07 10:50 | Journeys (call-backs, teams, switching business) | 29 | 0 (0%) | 67.9 s | 2 |
| [app-2026-10-07T13-06-32.jsonl](runs/app-2026-10-07T13-06-32.jsonl) | 2026-10-07 13:06 | Journeys (call-backs, teams, switching business) | 338 | 25 (7%) | 95.2 s | 2 |
| [app-2026-10-07T13-36-13.jsonl](runs/app-2026-10-07T13-36-13.jsonl) | 2026-10-07 13:36 | Journeys (call-backs, teams, switching business) | 13 | 4 (30%) | 12.9 s | 2 |
| [app-2026-10-07T13-57-48.jsonl](runs/app-2026-10-07T13-57-48.jsonl) | 2026-10-07 13:57 | Journeys (call-backs, teams, switching business) | 48 | 22 (45%) | 13.7 s | 2 |
| [app-2026-10-07T14-56-28.jsonl](runs/app-2026-10-07T14-56-28.jsonl) | 2026-10-07 14:56 | Journeys (call-backs, teams, switching business) | 2 | 0 (0%) | 13.5 s | 2 |
| [app-2026-10-07T15-04-19.jsonl](runs/app-2026-10-07T15-04-19.jsonl) | 2026-10-07 15:04 | Journeys (call-backs, teams, switching business) | 2 | 0 (0%) | 26.5 s | 2 |
| [app-2026-10-07T15-12-28.jsonl](runs/app-2026-10-07T15-12-28.jsonl) | 2026-10-07 15:12 | Journeys (call-backs, teams, switching business) | 4 | 1 (25%) | 15.7 s | 2 |
| [app-2026-10-07T15-21-27.jsonl](runs/app-2026-10-07T15-21-27.jsonl) | 2026-10-07 15:21 | Journeys (call-backs, teams, switching business) | 157 | 31 (19%) | 13.7 s | 2 |
| [app-2026-10-07T23-13-00.jsonl](runs/app-2026-10-07T23-13-00.jsonl) | 2026-10-07 23:13 | Security (attackers trying to reach other people's data) | 28 | 8 (28%) | 7.6 s | 2 |
| [app-2026-10-07T23-46-39.jsonl](runs/app-2026-10-07T23-46-39.jsonl) | 2026-10-07 23:46 | Security (attackers trying to reach other people's data) | 50 | 44 (88%) | 7.2 s | 2 |
| [app-2026-10-08T00-48-38.jsonl](runs/app-2026-10-08T00-48-38.jsonl) | 2026-10-08 00:48 | Security (attackers trying to reach other people's data) | 41 | 29 (70%) | 8.9 s | 2 |
| [app-2026-10-08T01-32-08.jsonl](runs/app-2026-10-08T01-32-08.jsonl) | 2026-10-08 01:32 | Security (attackers trying to reach other people's data) | 53 | 35 (66%) | 8.9 s | 2 |
| [app-2026-10-08T02-32-31.jsonl](runs/app-2026-10-08T02-32-31.jsonl) | 2026-10-08 02:32 | Security (attackers trying to reach other people's data) | 60 | 37 (61%) | 8.5 s | 2 |
| [app-2026-10-08T03-42-50.jsonl](runs/app-2026-10-08T03-42-50.jsonl) | 2026-10-08 03:42 | Security (attackers trying to reach other people's data) | 23 | 15 (65%) | 7.5 s | 2 |
| [app-2026-10-08T04-10-27.jsonl](runs/app-2026-10-08T04-10-27.jsonl) | 2026-10-08 04:10 | Security (attackers trying to reach other people's data) | 8 | 3 (37%) | 9.4 s | 2 |
| [app-2026-10-08T04-23-42.jsonl](runs/app-2026-10-08T04-23-42.jsonl) | 2026-10-08 04:23 | Security (attackers trying to reach other people's data) | 5 | 4 (80%) | 9.0 s | 2 |
| [app-2026-10-08T04-31-54.jsonl](runs/app-2026-10-08T04-31-54.jsonl) | 2026-10-08 04:31 | Journeys (call-backs, teams, switching business) | 42 | 7 (16%) | 14.5 s | 2 |
| [app-2026-10-08T05-31-39.jsonl](runs/app-2026-10-08T05-31-39.jsonl) | 2026-10-08 05:31 | Journeys (call-backs, teams, switching business) | 41 | 2 (4%) | 16.0 s | 2 |
| [app-2026-10-08T06-31-56.jsonl](runs/app-2026-10-08T06-31-56.jsonl) | 2026-10-08 06:31 | Journeys (call-backs, teams, switching business) | 31 | 3 (9%) | 14.4 s | 2 |
| [app-2026-10-08T07-25-10.jsonl](runs/app-2026-10-08T07-25-10.jsonl) | 2026-10-08 07:25 | Journeys (call-backs, teams, switching business) | 32 | 2 (6%) | 12.4 s | 2 |
| [app-2026-10-08T08-16-18.jsonl](runs/app-2026-10-08T08-16-18.jsonl) | 2026-10-08 08:16 | Journeys (call-backs, teams, switching business) | 31 | 1 (3%) | 14.8 s | 2 |
| [app-2026-10-08T09-12-16.jsonl](runs/app-2026-10-08T09-12-16.jsonl) | 2026-10-08 09:12 | Journeys (call-backs, teams, switching business) | 31 | 1 (3%) | 17.0 s | 2 |
| [bench-qwen3_4b-instruct-2026-10-08T10-13-13.jsonl](runs/bench-qwen3_4b-instruct-2026-10-08T10-13-13.jsonl) | 2026-10-08 10:13 | Single calls, Journeys (call-backs, teams, switching business), Hard calls (long, tricky, other languages) | 69 | 23 (33%) | 11.9 s | 2 |
