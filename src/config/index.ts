import { PresenceService } from '../PresenceService';
import { PresenceConfig, PresenceError } from '../types';

let globalPresenceService: PresenceService | null = null;

/**
 * Configure a global presence service instance
 * This is useful for apps that want a singleton approach
 */
export function configurePresence(config: PresenceConfig): PresenceService {
  if (globalPresenceService) {
    console.warn('Global presence service already configured. Destroying previous instance.');
    globalPresenceService.destroy();
  }
  
  try {
    globalPresenceService = new PresenceService(config);
    return globalPresenceService;
  } catch (error) {
    throw new PresenceError(
      'Failed to configure global presence service',
      'CONFIG_FAILED',
      error as Error
    );
  }
}

/**
 * Get the global presence service instance
 */
export function getGlobalPresenceService(): PresenceService {
  if (!globalPresenceService) {
    throw new PresenceError(
      'Global presence service not configured. Call configurePresence() first.',
      'NOT_CONFIGURED'
    );
  }
  return globalPresenceService;
}

/**
 * Create a new presence service instance (non-global)
 */
export function createPresenceService(config: PresenceConfig): PresenceService {
  return new PresenceService(config);
}

/**
 * Destroy the global presence service
 */
export function destroyGlobalPresenceService(): void {
  if (globalPresenceService) {
    globalPresenceService.destroy();
    globalPresenceService = null;
  }
}
