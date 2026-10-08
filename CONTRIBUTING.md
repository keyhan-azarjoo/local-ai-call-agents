# Contributing

Thanks for your interest. Issues and pull requests are welcome.

1. Read [ARCHITECTURE.md](docs/ARCHITECTURE.md) to see how the parts fit together.
2. Keep changes small and focused, with a clear description of the behaviour they change.
3. Before opening a pull request, in `app/`:
   ```bash
   flutter analyze
   flutter test $(ls test/*_test.dart test/scenarios/*_test.dart | grep -v live_test)
   ```
4. Changes to call handling should come with a test: a unit test where possible (see `test/call_end_test.dart`), or new scenarios in `test/scenarios/generate.py`.
5. Never use real phone numbers or personal details in tests or examples. Use Ofcom's ranges reserved for drama (07700 900000–900999, 020 7946 0000–0999).

Security problems: please report them privately (see [SECURITY.md](docs/SECURITY.md)), not in a public issue.
