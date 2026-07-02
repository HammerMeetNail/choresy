// tests/e2e/chore-metrics.spec.js
// Phase 3 — generalized per-chore metrics: the "Track a value" picker in the
// chore editor and the auto-available per-chore analytics section.

import { test, expect } from '@playwright/test';

function uniqueEmail() {
  return `e2e-metrics-${Date.now()}-${Math.random().toString(36).slice(2, 6)}@test.com`;
}

async function setup(page, { seed = false } = {}) {
  await page.goto('/register');
  await page.waitForSelector('#register-form');
  await page.fill('#reg-email', uniqueEmail());
  await page.fill('#reg-password', 'test123456');
  await page.fill('#reg-confirm', 'test123456');
  await page.click('button[type="submit"]');
  await page.waitForSelector('#hh-indicator:not([hidden])', { timeout: 10000 });
  const csrf = (await page.context().cookies()).find(c => c.name === 'nabu_csrf')?.value || '';
  await page.request.post('/api/household', {
    data: { name: `Metrics ${Date.now()}` },
    headers: { 'X-CSRF-Token': csrf },
  });
  if (seed) {
    await page.request.post('/api/chores/seed-defaults', { headers: { 'X-CSRF-Token': csrf } });
  }
  await page.reload();
  await page.waitForSelector('a[data-nav="stats"]', { timeout: 15000 });
  return { csrf };
}

test.describe('Chore metrics (Phase 3)', () => {
  test('metric picker persists amount type + unit across reopen', async ({ page }) => {
    await setup(page, { seed: true });

    await page.click('[data-action="switch-home-view"][data-view="manage"]');
    await page.waitForSelector('.chore-list', { timeout: 10000 });

    await page.click('.fab[data-action="chore-add"]');
    await page.waitForSelector('#chore-edit-name');
    await page.fill('#chore-edit-name', 'Weigh In');
    // Amount metric reveals the unit row.
    await expect(page.locator('.chore-metric-unit-row')).toBeHidden();
    await page.selectOption('#chore-metric-type', 'amount');
    await expect(page.locator('.chore-metric-unit-row')).toBeVisible();
    await page.fill('#chore-metric-unit', 'g');
    await page.click('[data-action="save-chore"]');

    await page.waitForSelector('.chore-list');
    await page.click('.chore-row:has-text("Weigh In") [data-action="chore-edit"]');
    await page.waitForSelector('#chore-metric-type');
    await expect(page.locator('#chore-metric-type')).toHaveValue('amount');
    await expect(page.locator('#chore-metric-unit')).toHaveValue('g');
  });

  test('a metric/indicator chore gets its own per-chore stats section', async ({ page }) => {
    const { csrf } = await setup(page);
    const res = await page.request.post('/api/chores', {
      data: { name: 'Meds', icon: '💊', color: '#A78BFA', indicatorLabels: ['am', 'pm'] },
      headers: { 'X-CSRF-Token': csrf },
    });
    const chore = (await res.json()).chore;
    await page.request.post('/api/logs', {
      data: { choreId: chore.id, indicators: ['am'] },
      headers: { 'X-CSRF-Token': csrf },
    });

    await page.reload();
    await page.click('a[data-nav="stats"]');
    await page.waitForSelector('.stats-page');
    // The generalized per-chore section renders the chore name in a card.
    await expect(page.locator('.stats-page')).toContainText('Meds');
  });
});
