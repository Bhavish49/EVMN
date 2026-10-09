# Contributing

Contributions are welcome. Bug reports, documentation improvements, and code changes that make the prototype easier to understand and safer to demonstrate are appreciated.

## Before you start

- Open an issue or discussion for substantial changes so the scope can be agreed before implementation.
- For a bug report, include the device/OS, Flutter version, steps to reproduce, and relevant logs. Remove personal data from logs.
- Do not include real vehicle identifiers, personal information, private keys, credentials, or production secrets in issues or patches.

## Make a change

1. Fork the repository and create a focused branch from the default branch.
2. Keep changes scoped and explain user-visible behavior in the pull request.
3. Update documentation when setup steps, packet behavior, or platform support changes.
4. Run the checks relevant to your change:

   ```powershell
   flutter pub get
   flutter analyze
   flutter test
   ```

5. For native BLE or speech changes, build and manually check the affected Android or Windows target when possible. Include platform limitations in the pull request.
6. Open a pull request and describe the problem, the solution, and the checks performed. Add screenshots for meaningful UI changes.

## Safety expectations

- Treat this as an unauthenticated demonstration, not a safety-critical system.
- Do not claim reliable delivery, verified emergency status, or traffic priority.
- Preserve compatibility with existing messages where practical, or document protocol changes and their compatibility impact.
- Keep alerts advisory and avoid adding behavior that could distract a driver or encourage unsafe maneuvers.

## Code style

- Follow the existing Dart and platform-language conventions.
- Prefer small changes with clear names and focused responsibilities.
- Do not add new dependencies without explaining why they are needed.
