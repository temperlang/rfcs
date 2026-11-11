A list of things I think we need for making tempest the new temper. Some of this
might repeat things I've heard from other people on the team:

- Verify that so sensitive content remains.
  - If so, scrub history again.
  - Some less than ideal things can be edited without history scrubbing. It
    depends on team review to decide what matters.
- Maybe clean up notes or docs or other things.
  - It's *not* required to have all documentation perfect.
  - We should still do a pass to update docs to document new temper (tempest) in
    cases where old docs don't actually apply any more.
- Change all reference to "tempest" to saying "temper".
  - This includes "Tempest" or "TEMPEST" or other variations to their equivalent
    variations under the correct name.
- Pass at least the same tests in these libraries:
  - chromarite
  - hrefine
  - kelpto
  - ordable
  - temper-regex-engine
  - temper-regex-parser
  - wherewith
  - ... additional private libraries
  - Some of these might suggest new tests required in tempest before becoming
    temper.
- Review all open temperlang/temper issues and PRs for which should remain open.
  - Some bugs may have been fixed already in tempest.
  - PRs as they stand would be innapropriate for the new code base.