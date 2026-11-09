#!/usr/bin/env node
/* validate-review-skills.js — deterministic validator for repo-defined review
 * skills (.dmtools/review/*.json + their lens files + promptAppend wiring).
 *
 * FREE BY DESIGN: pure fs + JSON checks — no agent, no network, no quota.
 * Finding "is this lens any GOOD" is the filter leg's job (agent work); this
 * script only answers "is the configuration well-formed and loadable".
 *
 * Factory-shipped in dmtools-agents (scripts/); shown here in-repo for the
 * worked example. Run from the repo root:
 *   node .dmtools/review/validate-review-skills.js
 *
 * Exit 0 = valid, 1 = errors (warnings do not fail).
 */
'use strict';

const fs = require('fs');
const path = require('path');

const REVIEW_DIR = '.dmtools/review';
const CONFIG_PATH = '.dmtools/config.js';

// The universal base schema (audit/reviewer-pool-vision.md §2.2).
// AVOID MANDATORY FIELDS: only name + lens are required — everything else
// defaults to the safe general behavior (rounds all, enabled, filtered,
// non-required, normal weight, all tiers, no path limitation).
const REQUIRED_FIELDS = ['name', 'lens'];
const FIELD_TYPES = {
    roleLine: 'string', lens: 'string', name: 'string', model: 'string-or-null'
};
const BOOLEAN_FIELDS = ['isFiltered', 'isRequired', 'isEnabled'];
const TIERS = ['BLOCKING', 'IMPORTANT', 'SUGGESTION', 'NIT'];
const ROUND_FLAGS = ['first', 'hunks', 'all'];
const FILTER_WEIGHTS = ['low', 'normal', 'high'];
const KNOWN_FIELDS = ['name', 'roleLine', 'lens', 'mayRaise',
    'filterWeight', 'isFiltered', 'isRequired', 'rounds', 'triggerPaths',
    'options', 'model', 'isEnabled'];
// Fields a repo may tune on a FACTORY reviewer (same-name file) — the rest of
// the base schema is factory-owned there (contract + lens stay factory-authored).
const TUNABLE_ON_FACTORY = ['isEnabled', 'rounds', 'triggerPaths', 'options', 'model'];
const FACTORY_REVIEWERS = ['base', 'security'];

const errors = [];
const warnings = [];
const infos = [];
let checked = 0;

function fail(file, msg) { errors.push(file + ': ' + msg); }
function warn(file, msg) { warnings.push(file + ': ' + msg); }
function info(file, msg) { infos.push(file + ': ' + msg); }

function checkSkillFile(file, full) {
    checked++;
    let spec;
    try {
        spec = JSON.parse(fs.readFileSync(full, 'utf8'));
    } catch (e) {
        fail(file, 'invalid JSON — ' + e.message);
        return null;
    }

    // Required: name + lens only (avoid mandatory fields — fewer errors).
    for (const f of REQUIRED_FIELDS) {
        if (typeof spec[f] !== 'string' || !spec[f].trim()) fail(file, 'missing/empty required field: ' + f);
    }
    // Typo protection: unknown top-level fields are warned (options is the
    // opaque pass-through bucket — unknown keys there are informational).
    Object.keys(spec).forEach(k => {
        if (!KNOWN_FIELDS.includes(k)) warn(file, 'unknown field "' + k + '" (typo? move reviewer-specific data under "options")');
    });

    if (spec.mayRaise !== undefined) {
        if (!Array.isArray(spec.mayRaise) || spec.mayRaise.length === 0) {
            fail(file, 'mayRaise must be a non-empty array of tiers');
        } else {
            spec.mayRaise.forEach(t => { if (!TIERS.includes(t)) fail(file, 'mayRaise has unknown tier: ' + JSON.stringify(t)); });
        }
    }
    // default mayRaise = ALL tiers including BLOCKING — no limits (owner: even
    // a translator's "wink → wank" catch is a legitimate blocker). The
    // citation discipline rides the base contract files every reviewer gets.
    if (spec.filterWeight !== undefined && !FILTER_WEIGHTS.includes(spec.filterWeight)) {
        fail(file, 'filterWeight must be one of: ' + FILTER_WEIGHTS.join(', '));
    } // default: "normal"
    BOOLEAN_FIELDS.forEach(b => {
        if (spec[b] !== undefined && typeof spec[b] !== 'boolean') fail(file, b + ' must be a boolean (defaults: isFiltered=true, isRequired=false, isEnabled=true)');
    });
    if (spec.rounds !== undefined) {
        if (!Array.isArray(spec.rounds) || spec.rounds.length === 0) {
            fail(file, 'rounds must be a non-empty array of flags (default: ["all"])');
        } else {
            spec.rounds.forEach(f => { if (!ROUND_FLAGS.includes(f)) fail(file, 'rounds has unknown flag: ' + JSON.stringify(f) + ' (valid: ' + ROUND_FLAGS.join(', ') + ')'); });
            if (spec.rounds.includes('all') && spec.rounds.length > 1) fail(file, 'rounds ["all"] is the whole set — do not combine with other flags');
        }
    } // default: ["all"]
    if (spec.triggerPaths !== undefined && !Array.isArray(spec.triggerPaths)) fail(file, 'triggerPaths must be an array of path substrings'); // default: [] = any new hunk
    if (spec.model !== undefined && spec.model !== null && typeof spec.model !== 'string') fail(file, 'model must be a string or null');

    // Lens file must exist in the repo and be non-empty.
    if (typeof spec.lens === 'string' && spec.lens.trim()) {
        const lensFull = path.resolve(spec.lens);
        if (!fs.existsSync(lensFull)) {
            fail(file, 'lens file not found: ' + spec.lens);
        } else if (fs.statSync(lensFull).size < 40) {
            fail(file, 'lens file is (nearly) empty: ' + spec.lens);
        } else if (spec.mayRaise !== undefined && spec.mayRaise.includes('BLOCKING')) {
            // nudge only for specs that EXPLICITLY declare BLOCKING — minimal
            // files inherit the citation discipline from the base contract.
            const lensText = fs.readFileSync(lensFull, 'utf8');
            if (!/citation|quote|file:line|:\\d+/i.test(lensText)) {
                warn(file, 'declares BLOCKING but the lens never mentions the citation discipline (quote + file:line) — 🚨 without evidence is the gh-1351 pathology');
            }
        }
    }

    // Factory reviewers are tuned via same-name files, not re-defined.
    if (FACTORY_REVIEWERS.includes(spec.name)) {
        for (const owned of ['roleLine', 'lens', 'mayRaise', 'filterWeight', 'isFiltered', 'isRequired']) {
            if (spec[owned] !== undefined) {
                fail(file, 'factory reviewer "' + spec.name + '" is tuned, not re-defined: field "' +
                    owned + '" is factory-owned (allowed here: ' + TUNABLE_ON_FACTORY.join(', ') + ')');
            }
        }
        info(file, 'tunes factory reviewer "' + spec.name + '"');
    } else if (spec.name === 'base') {
        fail(file, '"base" is the factory base reviewer — it cannot be defined or disabled from a repo');
    }

    // options: opaque by design — unknown keys are informational only.
    if (spec.options && typeof spec.options === 'object') {
        Object.keys(spec.options).forEach(k => info(file, 'options.' + k + ' (opaque pass-through)'));
    }
    return spec;
}

function main() {
    if (!fs.existsSync(REVIEW_DIR)) {
        console.log('validate-review-skills: no ' + REVIEW_DIR + '/ — repo uses factory defaults only (base + security). Nothing to validate.');
        process.exit(0);
    }

    // 1. Skill files.
    const names = {};
    const files = fs.readdirSync(REVIEW_DIR).filter(f => f.endsWith('.json'));
    if (files.length === 0) console.log('(no skill files — factory defaults only)');
    const specs = {};
    files.forEach(f => {
        const spec = checkSkillFile(f, path.join(REVIEW_DIR, f));
        if (!spec) return;
        if (names[spec.name]) fail(f, 'duplicate reviewer name "' + spec.name + '" (also in ' + names[spec.name] + ')');
        names[spec.name] = f;
        specs[spec.name] = spec;
    });

    // 2. config.js: enablement + promptAppend wiring.
    let config = {};
    if (fs.existsSync(CONFIG_PATH)) {
        try { config = require(path.resolve(CONFIG_PATH)); }
        catch (e) { fail(CONFIG_PATH, 'config.js does not parse — ' + e.message); }
    } else {
        warn(CONFIG_PATH, 'no config.js — reviewers defined here are never enabled');
    }
    const policy = config.reviewPolicy || {};
    const reviewers = policy.reviewers || {};
    Object.keys(reviewers).forEach(name => {
        if (!FACTORY_REVIEWERS.includes(name) && !specs[name]) {
            fail(CONFIG_PATH, 'reviewPolicy.reviewers.' + name + ' is enabled but no skill file defines it (' + REVIEW_DIR + '/' + name + '.json)');
        }
        const r = reviewers[name] || {};
        if (r.isEnabled && typeof r.isEnabled !== 'boolean') fail(CONFIG_PATH, 'reviewers.' + name + '.isEnabled must be boolean');
    });

    // 3. promptAppend: keys must be real reviewers; files must exist.
    const appends = policy.promptAppend || {};
    Object.keys(appends).forEach(reviewr => {
        if (reviewr !== 'base' && !FACTORY_REVIEWERS.includes(reviewr) && !specs[reviewr] && !reviewers[reviewr]) {
            fail(CONFIG_PATH, 'promptAppend.' + reviewr + ' targets an unknown reviewer');
        }
        (Array.isArray(appends[reviewr]) ? appends[reviewr] : []).forEach(p => {
            if (!fs.existsSync(p)) fail(CONFIG_PATH, 'promptAppend.' + reviewr + ' file not found: ' + p);
            else if (p.indexOf('node_modules') !== -1) fail(CONFIG_PATH, 'promptAppend.' + reviewr + ' suspicious path: ' + p);
        });
    });

    // Report.
    console.log('validate-review-skills — ' + REVIEW_DIR + '/');
    console.log('  skill files checked: ' + checked);
    errors.forEach(e => console.log('  ❌ ' + e));
    warnings.forEach(w => console.log('  ⚠️  ' + w));
    infos.forEach(i => console.log('  ℹ️  ' + i));
    if (!errors.length) console.log('  ✅ valid (' + warnings.length + ' warning(s), ' + infos.length + ' note(s))');
    else console.log('  ❌ INVALID — ' + errors.length + ' error(s)');
    process.exit(errors.length ? 1 : 0);
}

main();
