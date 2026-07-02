// tests/e2e/stats-widgets.spec.js
// Phase 4 — secure user-defined stats widgets: the "+ Add widget" wizard, the
// rendered widget, XSS-inert titles, and removal.

import { test, expect } from '@playwright/test';

function uniqueEmail() {
  return `e2e-widgets-${Date.now()}-${Math.random().toString(36).slice(2, 6)}@test.com`;
}

async function setupWithChore(page) {
  await page.goto('/register');
  await page.waitForSelector('#register-form');
  await page.fill('#reg-email', uniqueEmail());
  await page.fill('#reg-password', 'test123456');
  await page.fill('#reg-confirm', 'test123456');
  await page.click('button[type="submit"]');
  await page.waitForSelector('#hh-indicator:not([hidden])', { timeout: 10000 });
  const csrf = (await page.context().cookies()).find(c => c.name === 'nabu_csrf')?.value || '';
  await page.request.post('/api/household', {
    data: { name: `Widgets ${Date.now()}` },
    headers: { 'X-CSRF-Token': csrf },
  });
  const res = await page.request.post('/api/chores', {
    data: { name: 'Bottle', icon: '🍼', color: '#EC4899', metricType: 'amount', metricUnit: 'mL' },
    headers: { 'X-CSRF-Token': csrf },
  });
  const chore = (await res.json()).chore;
  await page.request.post('/api/logs', {
    data: { choreId: chore.id, volumeML: 100 },
    headers: { 'X-CSRF-Token': csrf },
  });
  await page.reload();
  await page.waitForSelector('.home-grid', { timeout: 15000 });
  return { csrf, chore };
}

test.describe('Stats widgets (Phase 4)', () => {
  test('add a widget via the wizard and see it render', async ({ page }) => {
    await setupWithChore(page);
    await page.click('a[data-nav="stats"]');
    await page.waitForSelector('.stats-page');

    await page.click('button[data-action="toggle-customize-stats"]');
    await page.click('[data-action="widget-add"]');
    await page.waitForSelector('.widget-wizard-sheet');

    await page.fill('#widget-title', 'My Bottles');
    await page.check('.widget-chore-check input');
    await page.selectOption('#widget-metric', 'amount');
    await page.click('[data-action="widget-save"]');

    await expect(page.locator('.widget-card')).toContainText('My Bottles');
    // total of amount over the loaded window = 100 mL
    await expect(page.locator('.widget-card')).toContainText('100');
  });

  test('a malicious widget title renders inert (no script executes)', async ({ page }) => {
    const { csrf, chore } = await setupWithChore(page);
    await page.request.patch('/api/preferences', {
      data: {
        statsWidgets: [{
          type: 'total', metric: 'count', period: 'week', choreIds: [chore.id],
          title: '<img src=x onerror="window.__xss=1">',
        }],
      },
      headers: { 'X-CSRF-Token': csrf },
    });

    await page.reload();
    await page.click('a[data-nav="stats"]');
    await page.waitForSelector('.stats-page');
    await page.waitForTimeout(500); // give any (broken) onerror a chance to fire

    await expect(page.locator('.widget-card img')).toHaveCount(0);
    const xss = await page.evaluate(() => window.__xss);
    expect(xss).toBeUndefined();
    // The title text is present, escaped.
    await expect(page.locator('.widget-card')).toContainText('<img src=x');
  });

  test('remove a widget', async ({ page }) => {
    const { csrf, chore } = await setupWithChore(page);
    await page.request.patch('/api/preferences', {
      data: { statsWidgets: [{ type: 'total', metric: 'count', period: 'week', choreIds: [chore.id], title: 'Doomed' }] },
      headers: { 'X-CSRF-Token': csrf },
    });
    await page.reload();
    await page.click('a[data-nav="stats"]');
    await page.waitForSelector('.widget-card');
    await expect(page.locator('.widget-card')).toContainText('Doomed');

    await page.click('.widget-card .widget-remove-btn');
    await expect(page.locator('.widget-card')).toHaveCount(0);
  });
});
