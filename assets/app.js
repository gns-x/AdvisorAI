// AdvisorAI - Revolutionary Frontend JavaScript

document.addEventListener('DOMContentLoaded', function() {
    console.log('🚀 AdvisorAI Frontend - Revolutionary AI Assistant Platform');
    
    // Initialize all components
    initParticleSystem();
    initScrollAnimations();
    initInteractiveElements();
    initSmoothScrolling();
    initParallaxEffects();
    initTypingEffect();
    initGlowEffects();
    initPerformanceOptimizations();
});

// Particle System
function initParticleSystem() {
    const particleContainer = document.createElement('div');
    particleContainer.className = 'fixed inset-0 pointer-events-none z-0';
    document.body.appendChild(particleContainer);

    // Create particles
    for (let i = 0; i < 50; i++) {
        createParticle(particleContainer);
    }
}

function createParticle(container) {
    const particle = document.createElement('div');
    particle.className = 'particle absolute';
    
    // Random properties
    const size = Math.random() * 4 + 1;
    const colors = ['#3B82F6', '#8B5CF6', '#06B6D4', '#EC4899', '#10B981'];
    const color = colors[Math.floor(Math.random() * colors.length)];
    
    particle.style.cssText = `
        width: ${size}px;
        height: ${size}px;
        background: ${color};
        left: ${Math.random() * 100}%;
        top: ${Math.random() * 100}%;
        animation: particle-float ${Math.random() * 4 + 3}s ease-in-out infinite;
        animation-delay: ${Math.random() * 2}s;
        opacity: ${Math.random() * 0.5 + 0.2};
    `;
    
    container.appendChild(particle);
}

// Scroll Animations
function initScrollAnimations() {
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };
    
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('revealed');
                
                // Add stagger effect to children
                const children = entry.target.querySelectorAll('.animate-scale-in');
                children.forEach((child, index) => {
                    setTimeout(() => {
                        child.style.animationDelay = `${index * 0.1}s`;
                        child.style.opacity = '1';
                        child.style.transform = 'scale(1)';
                    }, index * 100);
                });
            }
        });
    }, observerOptions);
    
    // Observe elements
    const animateElements = document.querySelectorAll('.bg-gradient-to-b, .bg-black, .bg-gray-900');
    animateElements.forEach(el => {
        el.classList.add('scroll-reveal');
        observer.observe(el);
    });
}

// Interactive Elements
function initInteractiveElements() {
    // Add hover effects to cards
    const cards = document.querySelectorAll('.group');
    cards.forEach(card => {
        card.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-10px) scale(1.02)';
            this.style.boxShadow = '0 20px 40px rgba(59, 130, 246, 0.3)';
        });
        
        card.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0) scale(1)';
            this.style.boxShadow = 'none';
        });
    });
    
    // Add ripple effect to buttons
    const buttons = document.querySelectorAll('a[href], button');
    buttons.forEach(button => {
        button.addEventListener('click', function(e) {
            createRipple(e, this);
        });
    });
}

function createRipple(event, element) {
    const ripple = document.createElement('span');
    const rect = element.getBoundingClientRect();
    const size = Math.max(rect.width, rect.height);
    const x = event.clientX - rect.left - size / 2;
    const y = event.clientY - rect.top - size / 2;
    
    ripple.style.cssText = `
        position: absolute;
        width: ${size}px;
        height: ${size}px;
        left: ${x}px;
        top: ${y}px;
        background: rgba(255, 255, 255, 0.3);
        border-radius: 50%;
        transform: scale(0);
        animation: ripple 0.6s linear;
        pointer-events: none;
    `;
    
    element.style.position = 'relative';
    element.appendChild(ripple);
    
    setTimeout(() => ripple.remove(), 600);
}

// Smooth Scrolling
function initSmoothScrolling() {
    const links = document.querySelectorAll('a[href^="#"]');
    
    links.forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            
            const targetId = this.getAttribute('href');
            const targetElement = document.querySelector(targetId);
            
            if (targetElement) {
                const offsetTop = targetElement.offsetTop - 80;
                
                window.scrollTo({
                    top: offsetTop,
                    behavior: 'smooth'
                });
            }
        });
    });
}

// Parallax Effects
function initParallaxEffects() {
    let ticking = false;
    
    function updateParallax() {
        const scrolled = window.pageYOffset;
        const parallaxElements = document.querySelectorAll('.absolute');
        
        parallaxElements.forEach(element => {
            const speed = 0.5;
            const yPos = -(scrolled * speed);
            element.style.transform = `translateY(${yPos}px)`;
        });
        
        ticking = false;
    }
    
    function requestTick() {
        if (!ticking) {
            requestAnimationFrame(updateParallax);
            ticking = true;
        }
    }
    
    window.addEventListener('scroll', requestTick, { passive: true });
}

// Typing Effect
function initTypingEffect() {
    const heroText = document.querySelector('h1');
    if (!heroText) return;
    
    const text = heroText.textContent;
    heroText.textContent = '';
    heroText.style.opacity = '1';
    
    let i = 0;
    const typeWriter = () => {
        if (i < text.length) {
            heroText.textContent += text.charAt(i);
            i++;
            setTimeout(typeWriter, 50);
        }
    };
    
    // Start typing effect after a delay
    setTimeout(typeWriter, 1000);
}

// Glow Effects
function initGlowEffects() {
    const glowElements = document.querySelectorAll('.animate-glow');
    
    glowElements.forEach(element => {
        element.addEventListener('mouseenter', function() {
            this.style.filter = 'brightness(1.2) drop-shadow(0 0 20px rgba(59, 130, 246, 0.8))';
        });
        
        element.addEventListener('mouseleave', function() {
            this.style.filter = 'brightness(1) drop-shadow(0 0 10px rgba(59, 130, 246, 0.5))';
        });
    });
}

// Performance Optimizations
function initPerformanceOptimizations() {
    // Lazy load images
    const images = document.querySelectorAll('img[data-src]');
    const imageObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const img = entry.target;
                img.src = img.dataset.src;
                img.classList.remove('lazy');
                imageObserver.unobserve(img);
            }
        });
    });
    
    images.forEach(img => imageObserver.observe(img));
    
    // Debounce scroll events
    let scrollTimeout;
    window.addEventListener('scroll', () => {
        if (scrollTimeout) clearTimeout(scrollTimeout);
        scrollTimeout = setTimeout(() => {
            // Handle scroll end
        }, 100);
    }, { passive: true });
}

// Advanced Animations
function initAdvancedAnimations() {
    // Magnetic effect for buttons
    const magneticButtons = document.querySelectorAll('.btn-primary');
    
    magneticButtons.forEach(button => {
        button.addEventListener('mousemove', function(e) {
            const rect = this.getBoundingClientRect();
            const x = e.clientX - rect.left - rect.width / 2;
            const y = e.clientY - rect.top - rect.height / 2;
            
            this.style.transform = `translate(${x * 0.1}px, ${y * 0.1}px) scale(1.05)`;
        });
        
        button.addEventListener('mouseleave', function() {
            this.style.transform = 'translate(0, 0) scale(1)';
        });
    });
    
    // 3D tilt effect for cards
    const tiltCards = document.querySelectorAll('.feature-card');
    
    tiltCards.forEach(card => {
        card.addEventListener('mousemove', function(e) {
            const rect = this.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;
            const centerX = rect.width / 2;
            const centerY = rect.height / 2;
            const rotateY = ((x - centerX) / centerX) * 10;
            const rotateX = ((centerY - y) / centerY) * 10;
            
            this.style.transform = `perspective(1000px) rotateY(${rotateY}deg) rotateX(${rotateX}deg) translateZ(20px)`;
        });
        
        card.addEventListener('mouseleave', function() {
            this.style.transform = 'perspective(1000px) rotateY(0deg) rotateX(0deg) translateZ(0px)';
        });
    });
}

// Utility Functions
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

function throttle(func, limit) {
    let inThrottle;
    return function() {
        const args = arguments;
        const context = this;
        if (!inThrottle) {
            func.apply(context, args);
            inThrottle = true;
            setTimeout(() => inThrottle = false, limit);
        }
    };
}

// Analytics and Tracking
function initAnalytics() {
    // Track page views
    trackEvent('page_view', {
        page: window.location.pathname,
        title: document.title,
        timestamp: new Date().toISOString()
    });
    
    // Track button clicks
    document.addEventListener('click', function(e) {
        if (e.target.matches('a[href*="advisorai-production.up.railway.app"]')) {
            trackEvent('demo_click', {
                source: e.target.textContent.trim(),
                timestamp: new Date().toISOString()
            });
        }
        
        if (e.target.matches('a[href*="github.com"]')) {
            trackEvent('github_click', {
                source: e.target.textContent.trim(),
                timestamp: new Date().toISOString()
            });
        }
    });
}

function trackEvent(eventName, properties = {}) {
    // Replace with your analytics service
    console.log('📊 Event tracked:', eventName, properties);
    
    // Example: Google Analytics 4
    if (typeof gtag !== 'undefined') {
        gtag('event', eventName, properties);
    }
}

// Performance Monitoring
function initPerformanceMonitoring() {
    // Monitor Core Web Vitals
    if ('PerformanceObserver' in window) {
        const observer = new PerformanceObserver((list) => {
            for (const entry of list.getEntries()) {
                console.log('📈 Performance:', entry.name, entry.value);
            }
        });
        
        observer.observe({ entryTypes: ['largest-contentful-paint', 'first-input', 'layout-shift'] });
    }
    
    // Monitor memory usage
    if ('memory' in performance) {
        setInterval(() => {
            const memory = performance.memory;
            console.log('💾 Memory usage:', {
                used: Math.round(memory.usedJSHeapSize / 1048576) + ' MB',
                total: Math.round(memory.totalJSHeapSize / 1048576) + ' MB',
                limit: Math.round(memory.jsHeapSizeLimit / 1048576) + ' MB'
            });
        }, 30000);
    }
}

// Error Handling
function initErrorHandling() {
    window.addEventListener('error', function(e) {
        console.error('❌ Error:', e.error);
        trackEvent('error', {
            message: e.message,
            filename: e.filename,
            lineno: e.lineno,
            colno: e.colno
        });
    });
    
    window.addEventListener('unhandledrejection', function(e) {
        console.error('❌ Unhandled Promise Rejection:', e.reason);
        trackEvent('unhandled_rejection', {
            reason: e.reason
        });
    });
}

// Initialize additional features
document.addEventListener('DOMContentLoaded', function() {
    initAdvancedAnimations();
    initAnalytics();
    initPerformanceMonitoring();
    initErrorHandling();
    
    // Add loading animation
    const loader = document.querySelector('.loading');
    if (loader) {
        setTimeout(() => {
            loader.style.opacity = '0';
            setTimeout(() => loader.remove(), 500);
        }, 1000);
    }
});

// Export for global access
window.AdvisorAI = {
    trackEvent,
    debounce,
    throttle,
    createRipple,
    initParticleSystem
};

console.log('✨ AdvisorAI Frontend initialized successfully!');
