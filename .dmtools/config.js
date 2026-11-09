// Machine loop wiring for THIS repository (see dmtools-agents
// docs/machine-factory-integration.md §5a). The factory resolves leg →
// runner here; runner paths are repo-relative.
module.exports = {
  // Whose login is "the machine" — auto rework and pr_approved arming
  // fire only on PRs authored by this login.
  machineAuthor: 'ai-teammate',
  sm: {
    runners: {
      bug: '.dmtools/runners/fa-bug-dev.json',
      story: '.dmtools/runners/fa-story-dev.json',
      review: '.dmtools/runners/fa-review.json',
      rework: '.dmtools/runners/fa-rework.json'
    }
  },
  // Review pool: base + security are factory defaults (both enabled,
  // defined in dmtools-agents — this repo cannot change their contracts,
  // only EXTEND them additively). `legal` is defined by THIS repository in
  // .dmtools/review/legal.json and enabled below. promptAppend is ADDITIVE
  // ONLY: repo files are appended after the factory lens and before the
  // factory few-shots/verdict rules; factory files cannot be replaced or
  // removed (they are the machine contract — see .dmtools/review/README.md).
  reviewPolicy: {
    reviewers: {
      security: { isEnabled: true },
      legal: { isEnabled: true }
    },
    promptAppend: {
      base: ['.dmtools/review/base.append.md'],
      security: ['.dmtools/review/security.append.md']
    }
  }
};
