import React from 'react';
import { View, Text, StyleSheet, ViewStyle, TextStyle } from 'react-native';
import { useUserPresence } from '../hooks/useUserPresence';
import { PresenceState } from '../types';

interface PresenceIndicatorProps {
  userId: string;
  size?: 'small' | 'medium' | 'large';
  showStatus?: boolean;
  showLastSeen?: boolean;
  style?: ViewStyle;
  textStyle?: TextStyle;
  colors?: {
    online?: string;
    offline?: string;
    away?: string;
    busy?: string;
  };
}

const defaultColors = {
  online: '#4CAF50',
  offline: '#9E9E9E',
  away: '#FF9800',
  busy: '#F44336'
};

const sizes = {
  small: 8,
  medium: 12,
  large: 16
};

export const PresenceIndicator: React.FC<PresenceIndicatorProps> = ({
  userId,
  size = 'medium',
  showStatus = false,
  showLastSeen = false,
  style,
  textStyle,
  colors = defaultColors
}) => {
  const { presence, isOnline, lastSeen } = useUserPresence(userId);
  
  if (!presence) {
    return null;
  }

  const indicatorSize = sizes[size];
  const statusColor = colors[presence.state] || defaultColors[presence.state];

  const formatLastSeen = (date: Date | null): string => {
    if (!date) return 'Never';
    
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(diff / 3600000);
    const days = Math.floor(diff / 86400000);

    if (minutes < 1) return 'Just now';
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    return `${days}d ago`;
  };

  return (
    <View style={[styles.container, style]}>
      <View
        style={[
          styles.indicator,
          {
            width: indicatorSize,
            height: indicatorSize,
            backgroundColor: statusColor,
            borderRadius: indicatorSize / 2
          }
        ]}
      />
      {showStatus && (
        <Text style={[styles.statusText, textStyle]}>
          {presence.state.charAt(0).toUpperCase() + presence.state.slice(1)}
        </Text>
      )}
      {showLastSeen && !isOnline && lastSeen && (
        <Text style={[styles.lastSeenText, textStyle]}>
          {formatLastSeen(lastSeen)}
        </Text>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center'
  },
  indicator: {
    marginRight: 6
  },
  statusText: {
    fontSize: 14,
    fontWeight: '500',
    marginRight: 8
  },
  lastSeenText: {
    fontSize: 12,
    color: '#666',
    fontStyle: 'italic'
  }
});
