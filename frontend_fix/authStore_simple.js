import { create } from 'zustand';
import { authAPI } from '../services/api';

const useAuthStore = create((set, get) => ({
  user: null,
  loading: false,
  initialized: false,
  error: null,
  
  // Initialize auth by checking with backend
  initialize: async () => {
    set({ loading: true });
    try {
      const response = await authAPI.me();
      const user = response.data.user;
      
      set({
        user,
        loading: false,
        initialized: true
      });
    } catch (error) {
      set({
        user: null,
        loading: false,
        initialized: true
      });
    }
  },
  
  // Sign up
  signup: async (data) => {
    set({ loading: true, error: null });
    try {
      const response = await authAPI.signup(data);
      const { user } = response.data;
      
      set({ user, loading: false });
      return { success: true };
    } catch (error) {
      const message = error.response?.data?.error || 'Signup failed';
      set({ error: message, loading: false });
      return { success: false, error: message };
    }
  },
  
  // Login
  login: async (data) => {
    set({ loading: true, error: null });
    try {
      const response = await authAPI.login(data);
      const { user } = response.data;
      
      set({ user, loading: false });
      return { success: true };
    } catch (error) {
      const message = error.response?.data?.error || 'Login failed';
      set({ error: message, loading: false });
      return { success: false, error: message };
    }
  },
  
  // Logout
  logout: async () => {
    try {
      await authAPI.logout();
    } catch (error) {
      console.error('Logout error:', error);
    }
    
    localStorage.removeItem('user');
    set({ user: null, error: null });
  },
  
  // Update user
  updateUser: (userData) => {
    const updatedUser = { ...get().user, ...userData };
    localStorage.setItem('user', JSON.stringify(updatedUser));
    set({ user: updatedUser });
  },
  
  // Handle Google OAuth callback
  handleOAuthCallback: async () => {
    set({ loading: true, error: null });
    
    try {
      const response = await authAPI.me();
      const user = response.data.user;
      
      set({ user, initialized: true, loading: false });
      return { success: true };
    } catch (error) {
      const message = error.response?.data?.error || 'Google authentication failed';
      set({ error: message, initialized: true, loading: false });
      return { success: false, error: message };
    }
  },
  
  clearError: () => set({ error: null }),
}));

export default useAuthStore;
