import { useState, useCallback } from 'react';
import { PresenceState } from '../types';
import { usePresenceContext } from '../context/PresenceContext';
import { useConnectionStatus } from './useConnectionStatus';

export interface UsePresenceReturn {
  currentState: PresenceState['state'];
  isConnected: boolean;
  setOnline: (customData?: Record<string, any>) => Promise<void>;
  setOffline: (customData?: Record<string, any>) => Promise<void>;
  setAway: (customData?: Record<string, any>) => Promise<void>;
  setBusy: (customData?: Record<string, any>) => Promise<void>;
  setCustomState: (state: PresenceState['state'], customData?: Record<string, any>) => Promise<void>;
}

export const usePresence = (): UsePresenceReturn => {
  const { presenceService } = usePresenceContext();
  const { isConnected } = useConnectionStatus();
  const [currentState, setCurrentState] = useState<PresenceState['state']>(
    () => presenceService.getCurrentPresenceState()
  );

  const setOnline = useCallback(async (customData?: Record<string, any>) => {
    try {
      await presenceService.goOnline(customData);
      setCurrentState('online');
    } catch (error) {
      console.error('Failed to set online:', error);
      throw error;
    }
  }, [presenceService]);

  const setOffline = useCallback(async (customData?: Record<string, any>) => {
    try {
      await presenceService.goOffline(customData);
      setCurrentState('offline');
    } catch (error) {
      console.error('Failed to set offline:', error);
      throw error;
    }
  }, [presenceService]);

  const setAway = useCallback(async (customData?: Record<string, any>) => {
    try {
      await presenceService.setAway(customData);
      setCurrentState('away');
    } catch (error) {
      console.error('Failed to set away:', error);
      throw error;
    }
  }, [presenceService]);

  const setBusy = useCallback(async (customData?: Record<string, any>) => {
    try {
      await presenceService.setBusy(customData);
      setCurrentState('busy');
    } catch (error) {
      console.error('Failed to set busy:', error);
      throw error;
    }
  }, [presenceService]);

  const setCustomState = useCallback(async (
    state: PresenceState['state'],
    customData?: Record<string, any>
  ) => {
    try {
      await presenceService.setCustomPresenceState(state, customData);
      setCurrentState(state);
    } catch (error) {
      console.error('Failed to set custom state:', error);
      throw error;
    }
  }, [presenceService]);

  return {
    currentState,
    isConnected,
    setOnline,
    setOffline,
    setAway,
    setBusy,
    setCustomState
  };
};
