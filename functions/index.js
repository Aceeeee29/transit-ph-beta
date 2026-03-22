const admin = require('firebase-admin');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const logger = require('firebase-functions/logger');

admin.initializeApp();

function toSafeString(value, fallback = '') {
  if (typeof value === 'string') {
    return value.trim();
  }
  if (value === null || value === undefined) {
    return fallback;
  }
  return String(value).trim();
}

function toSafeBoolean(value) {
  return Boolean(value);
}

exports.syncUpdateCheckerToRemoteConfig = onDocumentWritten(
  'app_config/update_checker',
  async (event) => {
    const afterData = event.data?.after?.data();

    if (!afterData) {
      logger.info('update_checker document deleted; skipping Remote Config sync.');
      return;
    }

    const latestVersion = toSafeString(afterData.latest_version, '1.0.0');
    const updateUrl = toSafeString(afterData.update_url, '');
    const forceUpdate = toSafeBoolean(afterData.force_update);
    const updateMessage = toSafeString(afterData.update_message, '');

    const remoteConfig = admin.remoteConfig();

    try {
      const template = await remoteConfig.getTemplate();

      template.parameters = {
        ...(template.parameters || {}),
        latest_version: {
          defaultValue: { value: latestVersion },
        },
        update_url: {
          defaultValue: { value: updateUrl },
        },
        force_update: {
          defaultValue: { value: forceUpdate ? 'true' : 'false' },
        },
        update_message: {
          defaultValue: { value: updateMessage },
        },
      };

      await remoteConfig.publishTemplate(template);

      logger.info('Remote Config synced from app_config/update_checker', {
        latest_version: latestVersion,
        force_update: forceUpdate,
      });
    } catch (error) {
      logger.error('Failed to sync update_checker to Remote Config', error);
      throw error;
    }
  },
);
