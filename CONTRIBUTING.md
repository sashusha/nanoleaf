# Contributing

Small, tested fixes and hardware reports are welcome. This is maintained for the
author’s own use; responses, reviews, and fixes are not guaranteed.

## Reports and changes

Use GitHub issues for bugs and proposals, and pull requests for changes. Search
existing issues first. Include what you expected, what happened, steps to
reproduce, macOS and app release versions, and relevant `nanoleaf status --verbose`
output. Review output and logs for personal information before posting; share
only the relevant excerpts.

Discuss substantial features or refactors before implementing them. Keep pull
requests focused and explain the change, tests run, and hardware actually tested.
For code changes, run:

```sh
swift run --build-system native NanoleafChecks
swift build --build-system native -c release --product nanoleaf
```

Add regression coverage when it tests a meaningful failure. Do not present mocked
USB tests as physical verification. For calibration changes, follow
[the calibration instructions](CALIBRATION.md).

AI-assisted contributions are welcome; understand and test what you submit.

## Expectations

Keep discussion technical and respectful. Disagreement is fine; personal attacks,
harassment, and repeated pressure for responses are not. The maintainer may decline
changes or close and lock unproductive discussions. Please use public GitHub
issues rather than private messages for ordinary support. Forks are welcome if
your goals differ from the project’s scope.
