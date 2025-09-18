import { useState, useEffect } from 'react';
import { PresenceState } from '../types';
import { usePresenceContext } from '../context/PresenceContext';

export interface MultipleUsersPresence {
  [userId: string]: PresenceState | null;
}

export interface UseMultipleUsersPresenceReturn {
  presences: MultipleUsersPresence;
  onlineUsers: string[];
  offlineUsers: string[];
  awayUsers: string[];
  busyUsers: string[];
  getPresence: (userId: string) => PresenceState | null;
  isUserOnline: (userId: string) => boolean;
}

export const useMultipleUsersPresence = (userIds: string[]): UseMultipleUsersPresenceReturn => {
  const { presenceService } = usePresenceContext();
  const [presences, setPresences] = useState<MultipleUsersPresence>({});

  useEffect(() => {
    const unsubscribeFunctions: Array<() => void> = [];
    const newPresences: MultipleUsersPresence = {};

    userIds.forEach(userId => {
      if (!userId) return;
      
      newPresences[userId] = null;
      
      const unsubscribe = presenceService.subscribeToUserPresence(
        userId,
        (presence: PresenceState | null) => {
          setPresences(prev => ({
            ...prev,
            [userId]: presence
          }));
        }
      );
      
      unsubscribeFunctions.push(unsubscribe);
    });

    setPresences(newPresences);

    return () => {
      unsubscribeFunctions.forEach(unsubscribe => unsubscribe());
    };
  }, [userIds, presenceService]);

  const onlineUsers = Object.entries(presences)
    .filter(([_, presence]) => presence?.state === 'online')
    .map(([userId]) => userId);

  const offlineUsers = Object.entries(presences)
    .filter(([_, presence]) => presence?.state === 'offline')
    .map(([userId]) => userId);

  const awayUsers = Object.entries(presences)
    .filter(([_, presence]) => presence?.state === 'away')
    .map(([userId]) => userId);

  const busyUsers = Object.entries(presences)
    .filter(([_, presence]) => presence?.state === 'busy')
    .map(([userId]) => userId);

  const getPresence = (userId: string): PresenceState | null => {
    return presences[userId] || null;
  };

  const isUserOnline = (userId: string): boolean => {
    return presences[userId]?.state === 'online';
  };

  return {
    presences,
    onlineUsers,
    offlineUsers,
    awayUsers,
    busyUsers,
    getPresence,
    isUserOnline
  };
};
