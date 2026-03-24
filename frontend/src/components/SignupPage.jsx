/**
 * Signup Component - User registration form
 * 
 * Features:
 * - Email/password registration
 * - Cookie-based authentication (automatic)
 * - Form validation
 * - Redirect after successful signup
 */

import React, { useState } from 'react';
import { Link, useNavigate, Navigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';

export function SignupPage() {
  const navigate = useNavigate();
  const { signup, isAuthenticated, error, clearError } = useAuth();
  
  // Form state
  const [formData, setFormData] = useState({
    email: '',
    password: '',
    passwordConfirmation: '',
    firstName: '',
    lastName: ''
  });
  
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [formError, setFormError] = useState('');
  
  // Redirect if already authenticated
  if (isAuthenticated) {
    return <Navigate to="/" replace />;
  }
  
  // Handle input change
  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value
    }));
    // Clear errors when user types
    setFormError('');
    clearError();
  };
  
  // Handle form submission
  const handleSubmit = async (e) => {
    e.preventDefault();
    
    // Validation
    if (!formData.email || !formData.password) {
      setFormError('Please fill in all required fields');
      return;
    }
    
    if (!formData.email.includes('@')) {
      setFormError('Please enter a valid email address');
      return;
    }
    
    if (formData.password.length < 8) {
      setFormError('Password must be at least 8 characters');
      return;
    }
    
    if (formData.password !== formData.passwordConfirmation) {
      setFormError('Passwords do not match');
      return;
    }
    
    setIsSubmitting(true);
    setFormError('');
    
    // Prepare signup data
    const signupData = {
      email: formData.email,
      password: formData.password,
      password_confirmation: formData.passwordConfirmation
    };
    
    // Add optional fields
    if (formData.firstName) signupData.first_name = formData.firstName;
    if (formData.lastName) signupData.last_name = formData.lastName;
    
    // Attempt signup
    const result = await signup(signupData);
    
    if (!result.success) {
      setFormError(result.error || 'Signup failed');
    }
    
    setIsSubmitting(false);
  };
  
  return (
    <div className="signup-page">
      <div className="signup-container">
        <div className="signup-header">
          <h1>Create Account</h1>
          <p>Sign up to get started with Warranty Vault</p>
        </div>
        
        {/* Error Display */}
        {formError && (
          <div className="alert alert-error">
            <span className="alert-icon">❌</span>
            <span>{formError}</span>
          </div>
        )}
        
        {/* Signup Form */}
        <form onSubmit={handleSubmit} className="signup-form" noValidate>
          <div className="form-row">
            <div className="form-group">
              <label htmlFor="firstName">First Name</label>
              <input
                type="text"
                id="firstName"
                name="firstName"
                value={formData.firstName}
                onChange={handleChange}
                placeholder="John"
                autoComplete="given-name"
                disabled={isSubmitting}
              />
            </div>
            
            <div className="form-group">
              <label htmlFor="lastName">Last Name</label>
              <input
                type="text"
                id="lastName"
                name="lastName"
                value={formData.lastName}
                onChange={handleChange}
                placeholder="Doe"
                autoComplete="family-name"
                disabled={isSubmitting}
              />
            </div>
          </div>
          
          <div className="form-group">
            <label htmlFor="email">Email Address</label>
            <input
              type="email"
              id="email"
              name="email"
              value={formData.email}
              onChange={handleChange}
              placeholder="you@example.com"
              autoComplete="email"
              disabled={isSubmitting}
              required
            />
          </div>
          
          <div className="form-group">
            <label htmlFor="password">Password</label>
            <input
              type="password"
              id="password"
              name="password"
              value={formData.password}
              onChange={handleChange}
              placeholder="At least 8 characters"
              autoComplete="new-password"
              disabled={isSubmitting}
              required
            />
            <span className="form-hint">Must be at least 8 characters</span>
          </div>
          
          <div className="form-group">
            <label htmlFor="passwordConfirmation">Confirm Password</label>
            <input
              type="password"
              id="passwordConfirmation"
              name="passwordConfirmation"
              value={formData.passwordConfirmation}
              onChange={handleChange}
              placeholder="Re-enter your password"
              autoComplete="new-password"
              disabled={isSubmitting}
              required
            />
          </div>
          
          <button 
            type="submit" 
            className="btn btn-primary btn-signup"
            disabled={isSubmitting}
          >
            {isSubmitting ? 'Creating account...' : 'Create Account'}
          </button>
        </form>
        
        {/* Login Link */}
        <div className="signup-footer">
          <p>
            Already have an account?{' '}
            <Link to="/login" className="login-link">
              Sign in
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}

export default SignupPage;
