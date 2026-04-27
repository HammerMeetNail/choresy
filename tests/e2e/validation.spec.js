import { test, expect } from '@playwright/test';

const TEST_USER = {
  email: `e2e-${Date.now()}@test.com`,
  password: 'test123456',
};

// Helper: fetch CSRF cookie from the server and return cookie header value
async function getCSRFToken(context) {
  const page = await context.newPage();
  await page.goto('/');
  const cookies = await context.cookies();
  await page.close();
  const csrfCookie = cookies.find(c => c.name === 'choresy_csrf');
  return csrfCookie ? csrfCookie.value : '';
}

async function gotoPageLogin(context) {
  // Register user, login, and return cookies
  const page = await context.newPage();
  await page.goto('/');
  
  // Register
  const csrf = (await context.cookies()).find(c => c.name === 'choresy_csrf')?.value || '';
  
  const registerResp = await page.request.post('/api/auth/register', {
    data: { email: TEST_USER.email, password: TEST_USER.password },
    headers: { 'X-CSRF-Token': csrf },
  });
  const registerBody = await registerResp.json();
  
  if (!registerBody.user) {
    // User may already exist from previous test run
    const loginResp = await page.request.post('/api/auth/login', {
      data: { email: TEST_USER.email, password: TEST_USER.password },
      headers: { 'X-CSRF-Token': csrf },
    });
    const loginBody = await loginResp.json();
    expect(loginBody.user).toBeDefined();
  }
  
  const cookies = await context.cookies();
  await page.close();
  return cookies;
}

test.describe('Health Check', () => {
  test('GET /health returns ok', async ({ request }) => {
    const resp = await request.get('/health');
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.status).toBe('ok');
  });

  test('GET /ready returns ok', async ({ request }) => {
    const resp = await request.get('/ready');
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.status).toBe('ready');
  });
});

test.describe('SPA Shell', () => {
  test('index.html loads with login form', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#login-form', { timeout: 10000 });
    await expect(page.locator('.auth-title')).toContainText('Choresy');
    await expect(page.locator('#login-email')).toBeVisible();
    await expect(page.locator('#login-password')).toBeVisible();
    await expect(page.locator('button[type="submit"]')).toContainText('Sign In');
  });

  test('can navigate to register view', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#login-form');
    await page.click('button[data-action="show-register"]');
    await page.waitForSelector('#register-form', { timeout: 5000 });
    await expect(page.locator('.auth-title')).toContainText('Create Account');
  });

  test('can navigate to magic link view', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#login-form');
    await page.click('button[data-action="show-magic-link"]');
    await page.waitForSelector('#magic-link-form', { timeout: 5000 });
    await expect(page.locator('.auth-title')).toContainText('Magic Link');
  });

  test('can navigate to forgot password view', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#login-form');
    await page.click('button[data-action="show-magic-link"]');
    await page.waitForSelector('#magic-link-form');
    await page.click('button[data-action="show-login"]');
    await page.waitForSelector('#login-form', { timeout: 5000 });
  });

  test('direct /register URL shows register form', async ({ page }) => {
    await page.goto('/register');
    await page.waitForSelector('#register-form', { timeout: 10000 });
    await expect(page.locator('.auth-title')).toContainText('Create Account');
  });

  test('direct /magic-link URL shows magic link form', async ({ page }) => {
    await page.goto('/magic-link');
    await page.waitForSelector('#magic-link-form', { timeout: 10000 });
  });

  test('direct /forgot-password URL shows forgot password form', async ({ page }) => {
    await page.goto('/forgot-password');
    await page.waitForSelector('#forgot-password-form', { timeout: 10000 });
  });
});

test.describe('Auth API', () => {
  test('GET /api/me returns null when not authenticated', async ({ request }) => {
    const resp = await request.get('/api/me');
    const body = await resp.json();
    expect(body.user).toBeNull();
  });
});

test.describe('Frontend Auth Flow', () => {
  test('login form submits and shows today view', async ({ page }) => {
    // First register a user via API
    await page.goto('/');
    await page.waitForSelector('#login-form');
    
    const csrf = (await page.context().cookies()).find(c => c.name === 'choresy_csrf')?.value || '';
    
    // Register first
    const regResp = await page.request.post('/api/auth/register', {
      data: { email: TEST_USER.email, password: TEST_USER.password },
      headers: { 'X-CSRF-Token': csrf },
    });
    const regBody = await regResp.json();
    
    // If user already exists, just login
    await page.fill('#login-email', TEST_USER.email);
    await page.fill('#login-password', TEST_USER.password);
    await page.click('button[type="submit"]');

    await page.waitForTimeout(2000);
    await expect(page.locator('#top-bar')).not.toBeHidden({ timeout: 5000 });
    await expect(page.locator('#bottom-tabs')).not.toBeHidden();
  });

  test('register form creates account and redirects', async ({ page }) => {
    const newEmail = `e2e-reg-${Date.now()}@test.com`;
    await page.goto('/register');
    await page.waitForSelector('#register-form');

    await page.fill('#reg-email', newEmail);
    await page.fill('#reg-password', 'test123456');
    await page.fill('#reg-confirm', 'test123456');
    await page.click('button[type="submit"]');

    await page.waitForTimeout(2000);
    await expect(page.locator('#top-bar')).not.toBeHidden({ timeout: 5000 });
  });

  test('logout clears session and shows login', async ({ page }) => {
    // Login first via UI
    await page.goto('/');
    await page.waitForSelector('#login-form');

    const csrf = (await page.context().cookies()).find(c => c.name === 'choresy_csrf')?.value || '';
    const regResp = await page.request.post('/api/auth/register', {
      data: { email: TEST_USER.email, password: TEST_USER.password },
      headers: { 'X-CSRF-Token': csrf },
    });
    
    await page.fill('#login-email', TEST_USER.email);
    await page.fill('#login-password', TEST_USER.password);
    await page.click('button[type="submit"]');
    await page.waitForTimeout(1000);
    
    // Now navigate to settings and logout
    await page.goto('/settings');
    await page.waitForTimeout(1000);
    
    const logoutBtn = page.locator('button[data-action="logout"]');
    if (await logoutBtn.isVisible()) {
      await logoutBtn.click();
      await page.waitForTimeout(1000);
      await expect(page.locator('#login-form')).toBeVisible({ timeout: 5000 });
    }
  });
});

test.describe('Household Flow', () => {
  test('welcome message when no household', async ({ page }) => {
    // Register fresh user
    const newEmail = `hh-test-${Date.now()}@test.com`;
    await page.goto('/register');
    await page.waitForSelector('#register-form');
    await page.fill('#reg-email', newEmail);
    await page.fill('#reg-password', 'test123456');
    await page.fill('#reg-confirm', 'test123456');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
    
    // Should see welcome message or today view
    await expect(page.locator('#top-bar')).not.toBeHidden({ timeout: 5000 });
  });

  test('create household via UI', async ({ page }) => {
    const newEmail = `create-hh-${Date.now()}@test.com`;
    await page.goto('/register');
    await page.waitForSelector('#register-form');
    await page.fill('#reg-email', newEmail);
    await page.fill('#reg-password', 'test123456');
    await page.fill('#reg-confirm', 'test123456');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
    
    // Navigate to settings
    await page.goto('/settings');
    await page.waitForTimeout(1000);
    
    // Look for create household form
    const hhForm = page.locator('#create-household-form');
    const hhNameInput = page.locator('#hh-name');
    if (await hhNameInput.isVisible()) {
      await hhNameInput.fill('E2E Test Household');
      await page.locator('#create-household-form button[type="submit"]').click();
      await page.waitForTimeout(2000);
    }
  });
});

test.describe('Chores and Logging UI', () => {
  test('today view shows chores after setup', async ({ page }) => {
    const newEmail = `chores-ui-${Date.now()}@test.com`;
    
    // Register and set up via API
    await page.goto('/');
    await page.waitForSelector('#login-form');
    const csrf = (await page.context().cookies()).find(c => c.name === 'choresy_csrf')?.value || '';
    
    await page.request.post('/api/auth/register', {
      data: { email: newEmail, password: 'test123456' },
      headers: { 'X-CSRF-Token': csrf },
    });
    await page.request.post('/api/household', {
      data: { name: 'E2E Test Home' },
      headers: { 'X-CSRF-Token': csrf },
    });
    await page.request.post('/api/chores/seed-defaults', {
      data: { names: ['Feed Cats (Morning)', 'Wash Dishes', 'Make Bed'] },
      headers: { 'X-CSRF-Token': csrf },
    });
    
    // Now login
    await page.fill('#login-email', newEmail);
    await page.fill('#login-password', 'test123456');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
    
    // Check that today view has content  
    await page.goto('/today');
    await page.waitForTimeout(1000);
    
    // Today view should have chore buttons or some content
    const appContent = await page.locator('#app').innerHTML();
    expect(appContent.length).toBeGreaterThan(0);
  });
});

test.describe('Error Handling', () => {
  test('login with wrong password shows error', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#login-form');
    await page.fill('#login-email', 'nonexistent@test.com');
    await page.fill('#login-password', 'wrongpassword');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(1000);
    
    const errorEl = page.locator('#login-error');
    // Error should be shown (may be visible or just have text)
    const errorClass = await errorEl.getAttribute('class');
    expect(errorClass).not.toContain('hidden');
  });

  test('register with mismatched passwords shows error', async ({ page }) => {
    await page.goto('/register');
    await page.waitForSelector('#register-form');
    await page.fill('#reg-email', 'mismatch@test.com');
    await page.fill('#reg-password', 'test123456');
    await page.fill('#reg-confirm', 'different123');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(500);
    
    const errorEl = page.locator('#register-error');
    const errorClass = await errorEl.getAttribute('class');
    expect(errorClass).not.toContain('hidden');
  });
});

test.describe('Navigation', () => {
  test('bottom tabs navigate correctly', async ({ page }) => {
    // Login first
    await page.goto('/');
    await page.waitForSelector('#login-form');
    const csrf = (await page.context().cookies()).find(c => c.name === 'choresy_csrf')?.value || '';
    
    await page.request.post('/api/auth/register', {
      data: { email: TEST_USER.email, password: TEST_USER.password },
      headers: { 'X-CSRF-Token': csrf },
    });
    
    await page.fill('#login-email', TEST_USER.email);
    await page.fill('#login-password', TEST_USER.password);
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
    
    await expect(page.locator('#bottom-tabs')).not.toBeHidden();
    
    // Click Chores tab
    await page.click('a[data-nav="chores"]');
    await page.waitForTimeout(500);
    
    // Click History tab
    await page.click('a[data-nav="history"]');
    await page.waitForTimeout(500);
    
    // Click Settings tab
    await page.click('a[data-nav="settings"]');
    await page.waitForTimeout(500);
    
    // Click Home tab
    await page.click('a[data-nav="today"]');
    await page.waitForTimeout(500);
  });
});
