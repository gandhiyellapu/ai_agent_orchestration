#!/usr/bin/env node
/**
 * TD POC Watcher
 * ==============
 * Background process that monitors TD workflow sessions and updates POC state.
 *
 * Features:
 * - Polls TD for workflow session status
 * - Auto-retries failed workflows (up to MAX_RETRIES)
 * - Sends notifications (Slack, terminal)
 * - Updates .poc-state/current-poc.json
 *
 * Usage:
 *   node watcher.js          # Run in foreground
 *   node watcher.js --daemon # Run as background process
 *   node watcher.js --once   # Check once and exit
 */

import { readFileSync, writeFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { spawn, execFileSync } from 'child_process';

// ES Module __dirname equivalent
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PROJECT_ROOT = join(__dirname, '..', '..');

// Load environment from .env file
function loadEnv() {
  const envPath = join(PROJECT_ROOT, '.env');
  if (existsSync(envPath)) {
    const envContent = readFileSync(envPath, 'utf-8');
    envContent.split('\n').forEach(line => {
      // Skip comments and empty lines
      if (line.startsWith('#') || !line.trim()) return;
      const eqIndex = line.indexOf('=');
      if (eqIndex > 0) {
        const key = line.substring(0, eqIndex).trim();
        const value = line.substring(eqIndex + 1).trim();
        process.env[key] = value;
      }
    });
  }
}

loadEnv();

// Configuration
const CONFIG = {
  pollInterval: parseInt(process.env.POLL_INTERVAL_SECONDS || '60') * 1000,
  maxRetries: parseInt(process.env.MAX_RETRIES || '10'),
  retryDelay: parseInt(process.env.RETRY_DELAY_SECONDS || '300') * 1000,
  slackWebhook: process.env.SLACK_WEBHOOK_URL || '',
  terminalNotify: process.env.TERMINAL_NOTIFY !== 'false',
  tdSite: process.env.TD_SITE || 'us01',
  projectName: process.env.TD_PROJECT_NAME || 'retail-poc',
};

// State file paths
const STATE_DIR = join(PROJECT_ROOT, '.poc-state');
const STATE_FILE = join(STATE_DIR, 'current-poc.json');

// Colors for terminal output
const colors = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
};

function log(level, message) {
  const timestamp = new Date().toISOString();
  const color = {
    info: colors.blue,
    success: colors.green,
    warn: colors.yellow,
    error: colors.red,
  }[level] || colors.reset;

  console.log(`${color}[${timestamp}] [${level.toUpperCase()}]${colors.reset} ${message}`);
}

function loadState() {
  if (!existsSync(STATE_FILE)) {
    return null;
  }
  try {
    return JSON.parse(readFileSync(STATE_FILE, 'utf-8'));
  } catch (e) {
    log('error', `Failed to load state: ${e.message}`);
    return null;
  }
}

function saveState(state) {
  try {
    writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  } catch (e) {
    log('error', `Failed to save state: ${e.message}`);
  }
}

async function sendSlackNotification(message, isError = false) {
  if (!CONFIG.slackWebhook) {
    return;
  }

  try {
    const payload = {
      text: isError ? `:x: ${message}` : `:white_check_mark: ${message}`,
      username: 'TD POC Watcher',
      icon_emoji: isError ? ':warning:' : ':robot_face:',
    };

    const response = await fetch(CONFIG.slackWebhook, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      log('warn', `Slack notification failed: ${response.status}`);
    }
  } catch (e) {
    log('warn', `Slack notification error: ${e.message}`);
  }
}

function terminalNotify(title, message) {
  if (!CONFIG.terminalNotify) {
    return;
  }

  // macOS notification using osascript with safe argument passing
  try {
    // Using execFileSync with array arguments prevents shell injection
    execFileSync('osascript', [
      '-e',
      `display notification "${message.replace(/"/g, '\\"')}" with title "${title.replace(/"/g, '\\"')}"`
    ], { timeout: 5000 });
  } catch (e) {
    // Fallback: terminal bell
    process.stdout.write('\x07');
  }
}

/**
 * Check TD session status using td CLI.
 * Uses execFileSync with array arguments for safety.
 */
function checkTdSession(sessionId) {
  try {
    // Use execFileSync with separate arguments (no shell interpolation)
    const result = execFileSync('td', [
      'wf', 'sessions',
      '-p', CONFIG.projectName,
      '-o', 'json'
    ], {
      encoding: 'utf-8',
      timeout: 30000,
      stdio: ['pipe', 'pipe', 'pipe']
    });

    const sessions = JSON.parse(result);
    const session = sessions.find(s =>
      s.id === sessionId ||
      s.session_id === sessionId ||
      String(s.id) === String(sessionId)
    );

    if (!session) {
      return { status: 'unknown', error: 'Session not found' };
    }

    return {
      status: session.status || session.state || 'unknown',
      workflow: session.workflow_name || session.workflow,
      lastAttempt: session.last_attempt_id,
    };
  } catch (e) {
    log('warn', `Could not check TD session: ${e.message}`);
    return { status: 'unknown', error: e.message };
  }
}

/**
 * Retry a failed TD workflow session using td CLI.
 * Uses execFileSync with array arguments for safety.
 */
function retryWorkflow(sessionId) {
  try {
    log('info', `Retrying workflow session ${sessionId}...`);

    // Use execFileSync with separate arguments (no shell interpolation)
    execFileSync('td', [
      'wf', 'retry',
      String(sessionId)
    ], {
      encoding: 'utf-8',
      timeout: 30000,
      stdio: ['pipe', 'pipe', 'pipe']
    });

    log('success', `Retry initiated for session ${sessionId}`);
    return true;
  } catch (e) {
    log('error', `Failed to retry workflow: ${e.message}`);
    return false;
  }
}

async function poll() {
  const state = loadState();

  if (!state || !state.poc_id) {
    log('info', 'No active POC. Waiting...');
    return;
  }

  const activeSession = state.active_td_session;

  if (!activeSession) {
    log('info', `POC ${state.poc_id} - Stage: ${state.stage} - No active TD session`);
    return;
  }

  log('info', `Checking TD session ${activeSession}...`);

  const sessionStatus = checkTdSession(activeSession);

  if (sessionStatus.status === 'success') {
    // Workflow completed successfully
    log('success', `Workflow completed successfully!`);

    // Update state
    state.stages[state.stage].status = 'completed';
    state.stages[state.stage].completed_at = new Date().toISOString();
    state.active_td_session = null;
    saveState(state);

    // Send notifications
    const message = `POC ${state.poc_id}: Stage "${state.stage}" completed!`;
    await sendSlackNotification(message);
    terminalNotify('TD POC Complete', message);

  } else if (sessionStatus.status === 'error' || sessionStatus.status === 'failed') {
    // Workflow failed
    log('error', `Workflow failed!`);

    const currentStage = state.stages[state.stage] || {};
    const retryCount = (currentStage.retry_count || 0) + 1;
    state.stages[state.stage].retry_count = retryCount;

    if (retryCount < CONFIG.maxRetries) {
      log('info', `Retry ${retryCount}/${CONFIG.maxRetries} in ${CONFIG.retryDelay / 1000}s...`);

      state.stages[state.stage].status = 'retrying';
      state.stages[state.stage].next_retry_at = new Date(Date.now() + CONFIG.retryDelay).toISOString();
      saveState(state);

      // Wait before retry
      await new Promise(resolve => setTimeout(resolve, CONFIG.retryDelay));

      // Attempt retry
      const retried = retryWorkflow(activeSession);
      if (!retried) {
        state.stages[state.stage].status = 'failed';
        saveState(state);
      }

    } else {
      // Max retries exceeded
      log('error', `Max retries (${CONFIG.maxRetries}) exceeded. Human intervention needed.`);

      state.stages[state.stage].status = 'failed';
      state.stages[state.stage].failed_at = new Date().toISOString();
      state.active_td_session = null;

      if (!state.errors) state.errors = [];
      state.errors.push({
        stage: state.stage,
        error: sessionStatus.error || 'Max retries exceeded',
        timestamp: new Date().toISOString(),
      });
      saveState(state);

      // Send urgent notification
      const message = `POC ${state.poc_id}: Stage "${state.stage}" FAILED after ${CONFIG.maxRetries} retries!`;
      await sendSlackNotification(message, true);
      terminalNotify('TD POC Failed', message);
    }

  } else if (sessionStatus.status === 'running') {
    log('info', `Workflow still running...`);
  } else {
    log('warn', `Unknown session status: ${sessionStatus.status}`);
  }
}

async function runOnce() {
  log('info', 'Running single check...');
  await poll();
  log('info', 'Done.');
}

async function runLoop() {
  log('info', `TD POC Watcher started. Polling every ${CONFIG.pollInterval / 1000}s`);
  log('info', `Project: ${CONFIG.projectName}`);
  log('info', `Max retries: ${CONFIG.maxRetries}`);
  log('info', `Slack notifications: ${CONFIG.slackWebhook ? 'enabled' : 'disabled'}`);

  // Initial poll
  await poll();

  // Continuous polling
  setInterval(async () => {
    try {
      await poll();
    } catch (e) {
      log('error', `Poll error: ${e.message}`);
    }
  }, CONFIG.pollInterval);
}

function showHelp() {
  console.log(`
TD POC Watcher
==============

Usage:
  node watcher.js          Run watcher in foreground
  node watcher.js --once   Check once and exit
  node watcher.js --daemon Run as background process (nohup)
  node watcher.js --help   Show this help

Environment Variables (from .env):
  POLL_INTERVAL_SECONDS  How often to check (default: 60)
  MAX_RETRIES            Max retry attempts (default: 10)
  RETRY_DELAY_SECONDS    Delay between retries (default: 300)
  SLACK_WEBHOOK_URL      Slack webhook for notifications
  TERMINAL_NOTIFY        Enable macOS notifications (default: true)
  TD_PROJECT_NAME        TD project name
`);
}

// Main
const args = process.argv.slice(2);

if (args.includes('--help') || args.includes('-h')) {
  showHelp();
  process.exit(0);
}

if (args.includes('--once')) {
  runOnce().catch(e => {
    log('error', e.message);
    process.exit(1);
  });
} else if (args.includes('--daemon')) {
  // Fork as daemon using spawn with detached mode
  const child = spawn(process.argv[0], [__filename], {
    detached: true,
    stdio: 'ignore',
  });
  child.unref();
  console.log(`Watcher started in background (PID: ${child.pid})`);
  process.exit(0);
} else {
  runLoop().catch(e => {
    log('error', e.message);
    process.exit(1);
  });
}
