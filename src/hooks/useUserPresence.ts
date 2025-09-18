import { useState, useEffect } from 'react';
import { PresenceState } from '../types';
import { usePresenceContext } from '../context/PresenceContext';

export interface UseUserPresenceReturn {
  presence: PresenceState | null;
  isOnline: boolean;
  isOffline: boolean;
  isAway: boolean;
  isBusy: boolean;
  lastSeen: Date | null;
  customData?: Record<string, any>;
}

export const useUserPresence = (userId: string): UseUserPresenceReturn => {
  const { presenceService } = usePresenceContext();
  const [presence, setPresence] = useState<PresenceState | null>(null);

  useEffect(() => {
    if (!userId) {
      setPresence(null);
      return;
    }

    const unsubscribe = presenceService.subscribeToUserPresence(
      userId,
      (userPresence: PresenceState | null) => {
        setPresence(userPresence);
      }
    );

    return unsubscribe;
  }, [userId, presenceService]);

  const lastSeen = presence?.lastChanged 
    ? new Date(presence.lastChanged) 
    : null;

  return {
    presence,
    isOnline: presence?.state === 'online',
    isOffline: presence?.state === 'offline',
    isAway: presence?.state === 'away',
    isBusy: presence?.state === 'busy',
    lastSeen,
    customData: presence?.customData
  };
};
