import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  advisorIdentity,
  costUsd,
  countSession,
  safeModel,
  tokenPoints,
} from "./usage.ts";

describe("tokenPoints", () => {
  it("emits one point per positive token bucket", () => {
    assert.deepEqual(
      tokenPoints({ input: 10, output: 2, cacheRead: 0, cacheWrite: 4 }),
      [
        { type: "input", value: 10 },
        { type: "output", value: 2 },
        { type: "cacheWrite", value: 4 },
      ],
    );
  });

  it("drops non-finite and negative values", () => {
    assert.deepEqual(
      tokenPoints({ input: Number.NaN, output: -1, cacheRead: Number.POSITIVE_INFINITY }),
      [],
    );
  });
});

describe("costUsd", () => {
  it("uses Pi usage.cost.total when it is positive", () => {
    assert.equal(costUsd({ cost: { total: 0.0123 } }), 0.0123);
  });

  it("omits missing, zero, and negative cost", () => {
    assert.equal(costUsd({}), undefined);
    assert.equal(costUsd({ cost: { total: 0 } }), undefined);
    assert.equal(costUsd({ cost: { total: -0.1 } }), undefined);
  });
});

describe("labels", () => {
  it("splits provider/model and keeps a model id that contains slashes", () => {
    assert.deepEqual(advisorIdentity({ advisor: "openai/gpt-6-astra" }), {
      provider: "openai",
      model: "gpt-6-astra",
    });
    assert.deepEqual(
      advisorIdentity({ advisor: "openrouter/meta-llama/llama-3.3-70b-instruct:free" }),
      {
        provider: "openrouter",
        model: "meta-llama/llama-3.3-70b-instruct:free",
      },
    );
  });

  it("rejects path-like and free-text labels", () => {
    assert.equal(safeModel("../etc/passwd"), "unknown");
    assert.equal(safeModel("/Users/motoki/src"), "unknown");
    assert.equal(safeModel("hello world"), "unknown");
    assert.deepEqual(advisorIdentity({ advisor: "not a model", question: "secret" }), {
      provider: "unknown",
      model: "unknown",
    });
  });
});

describe("countSession", () => {
  it("skips reload and counts other start reasons", () => {
    assert.equal(countSession("reload"), false);
    assert.equal(countSession("startup"), true);
    assert.equal(countSession("resume"), true);
    assert.equal(countSession(undefined), true);
  });
});
