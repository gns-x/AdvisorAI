// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar.js"

// Custom Hooks
const Hooks = {
  AutoResize: {
    mounted() {
      this.resize()
      this.handleEvent("input", () => this.resize())
    },
    
    resize() {
      this.el.style.height = "auto"
      this.el.style.height = this.el.scrollHeight + "px"
    }
  },

  CursorStyleAutoResize: {
    mounted() {
      this.minHeight = 44
      this.resize()
      this.handleEvent("input", () => this.resize())
      
      // Handle paste events
      this.el.addEventListener('paste', () => {
        setTimeout(() => this.resize(), 0)
      })
      
      // Handle composition events for IME input
      this.el.addEventListener('compositionend', () => {
        this.resize()
      })
      
      // Handle Enter key to send message (prevent default new line)
      this.el.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault() // Prevent default new line behavior
          
          // Get the current message value
          const message = this.el.value.trim()
          
          if (message !== '') {
            // Push the send_message event to the LiveView
            this.pushEvent('send_message', { message: message })
            
            // Clear the textarea
            this.el.value = ''
            
            // Trigger resize to adjust height
            this.resize()
          }
        }
      })
    },
    
    resize() {
      // Reset height to auto to get the correct scrollHeight
      this.el.style.height = "auto"
      
      // Get the scroll height (natural height of content)
      const scrollHeight = this.el.scrollHeight
      
      // Set the height to match content (no max height limit like Cursor)
      this.el.style.height = scrollHeight + "px"
      
      // Always show scrollbar if needed
      this.el.style.overflowY = scrollHeight > this.minHeight ? "auto" : "hidden"
      
      // Adjust the entire input container
      this.adjustContainer()
    },
    
    adjustContainer() {
      const inputContainer = this.el.closest('.cursor-input-container')
      
      if (inputContainer) {
        const textareaHeight = this.el.scrollHeight
        const minHeight = 60 // Minimum height of the input container
        
        // Calculate the new height for the input container
        // Add extra padding for the buttons and spacing
        const newHeight = Math.max(minHeight, textareaHeight + 32)
        
        // Set the height of the input container
        inputContainer.style.height = newHeight + 'px'
        
        // Debug logging
        console.log('Textarea height:', textareaHeight, 'Container height:', newHeight)
        
        // Also adjust the parent container padding if needed
        const parentContainer = inputContainer.closest('.border-t')
        if (parentContainer) {
          if (textareaHeight > 100) {
            parentContainer.style.paddingTop = '8px'
            parentContainer.style.paddingBottom = '8px'
          } else {
            parentContainer.style.paddingTop = '16px'
            parentContainer.style.paddingBottom = '16px'
          }
        }
      } else {
        console.error('Could not find cursor-input-container')
      }
    }
  },
  
  VoiceRecorder: {
    mounted() {
      this.mediaRecorder = null
      this.audioChunks = []
      this.isRecording = false
      this.setupRecording()
    },
    
    setupRecording() {
      if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
        navigator.mediaDevices.getUserMedia({ audio: true })
          .then(stream => {
            this.mediaRecorder = new MediaRecorder(stream)
            this.setupMediaRecorder()
          })
          .catch(err => {
            console.error("Error accessing microphone:", err)
          })
      }
    },
    
    setupMediaRecorder() {
      this.mediaRecorder.ondataavailable = (event) => {
        this.audioChunks.push(event.data)
      }
      
      this.mediaRecorder.onstop = () => {
        const audioBlob = new Blob(this.audioChunks, { type: 'audio/wav' })
        this.audioChunks = []
        // Here you would typically send the audio to your server
        console.log("Audio recorded:", audioBlob)
      }
    },
    
    startRecording() {
      if (this.mediaRecorder && this.mediaRecorder.state === 'inactive') {
        this.mediaRecorder.start()
        this.isRecording = true
        this.el.classList.add('recording')
      }
    },
    
    stopRecording() {
      if (this.mediaRecorder && this.mediaRecorder.state === 'recording') {
        this.mediaRecorder.stop()
        this.isRecording = false
        this.el.classList.remove('recording')
      }
    }
  },
  
  MessageReactions: {
    mounted() {
      this.handleEvent("click", (e) => {
        if (e.target.classList.contains('reaction-btn')) {
          const reaction = e.target.textContent.trim().split(' ')[0]
          const countElement = e.target.querySelector('.count')
          const currentCount = parseInt(countElement.textContent)
          countElement.textContent = currentCount + 1
          
          // Send reaction to server
          this.pushEvent("add_reaction", {
            message_id: this.el.dataset.messageId,
            reaction: reaction
          })
        }
      })
    }
  },
  
  SmartReplies: {
    mounted() {
      this.handleEvent("click", (e) => {
        if (e.target.tagName === 'BUTTON' && e.target.classList.contains('smart-reply')) {
          const action = e.target.dataset.action
          this.pushEvent("quick_action", { action: action })
        }
      })
    }
  },
  
  ContextMenu: {
    mounted() {
      this.handleEvent("click", (e) => {
        if (e.target.classList.contains('context-option')) {
          const context = e.target.dataset.context
          this.pushEvent("set_context", { context: context })
          this.hideMenu()
        }
      })
      
      // Close menu when clicking outside
      document.addEventListener('click', (e) => {
        if (!this.el.contains(e.target)) {
          this.hideMenu()
        }
      })
    },
    
    hideMenu() {
      this.el.classList.add('hidden')
    }
  },
  
  TypingIndicator: {
    mounted() {
      this.typingTimeout = null
      this.handleEvent("input", () => {
        this.startTyping()
      })
    },
    
    startTyping() {
      this.pushEvent("typing_start")
      
      if (this.typingTimeout) {
        clearTimeout(this.typingTimeout)
      }
      
      this.typingTimeout = setTimeout(() => {
        this.pushEvent("typing_stop")
      }, 3000)
    }
  },

  // New hook for managing chat layout
  ChatLayout: {
    mounted() {
      this.scrollToBottom()
      this.handleEvent("new_message", () => {
        setTimeout(() => this.scrollToBottom(), 100)
      })
    },
    
    scrollToBottom() {
      const messagesContainer = document.getElementById('messages')
      if (messagesContainer) {
        messagesContainer.scrollTop = messagesContainer.scrollHeight
      }
    }
  },

  // Conversation menu hook
  ConversationMenu: {
    mounted() {
      this.menu = this.el.querySelector('.conversation-menu')
      this.button = this.el.querySelector('button')
      
      // Toggle menu on button click
      this.button.addEventListener('click', (e) => {
        e.preventDefault()
        e.stopPropagation()
        this.toggleMenu()
      })
      
      // Close menu when clicking outside
      document.addEventListener('click', (e) => {
        if (!this.el.contains(e.target)) {
          this.hideMenu()
        }
      })
      
      // Close menu when pressing Escape
      document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
          this.hideMenu()
        }
      })
    },
    
    toggleMenu() {
      if (this.menu.classList.contains('hidden')) {
        this.showMenu()
      } else {
        this.hideMenu()
      }
    },
    
    showMenu() {
      this.menu.classList.remove('hidden')
    },
    
    hideMenu() {
      this.menu.classList.add('hidden')
    }
  },
  
  LoadingState: {
    mounted() {
      this.handleEvent("update_loading", ({loading}) => {
        console.log("Loading state updated:", loading)
        // The LiveView will handle the template update automatically
      })
    }
  },

  // Animated Gradient Background Hook
  AnimatedGradientBg: {
    mounted() {
      this.updateGradient();
      this.timer = setInterval(() => this.updateGradient(), 60000);
    },
    destroyed() {
      clearInterval(this.timer);
    },
    updateGradient() {
      // Example: Animate based on time of day
      const hour = new Date().getHours();
      let mesh = '--gradient-mesh-1';
      if (hour >= 18 || hour < 6) {
        mesh = '--gradient-mesh-2'; // Evening/Night
      } else if (hour >= 12 && hour < 18) {
        mesh = '--gradient-mesh-3'; // Afternoon
      }
      document.body.style.setProperty('background', `var(${mesh})`);
    }
  },

  // Parallax and Glass Blur Hook
  ParallaxGlass: {
    mounted() {
      this.handleScroll = this.handleScroll.bind(this);
      window.addEventListener('scroll', this.handleScroll, { passive: true });
      this.handleScroll();
    },
    destroyed() {
      window.removeEventListener('scroll', this.handleScroll);
    },
    handleScroll() {
      const scrollY = window.scrollY || window.pageYOffset;
      // Parallax effect
      this.el.style.transform = `translateY(${scrollY * 0.08}px)`;
      // Dynamic blur
      this.el.style.backdropFilter = `blur(${12 + Math.min(scrollY / 30, 24)}px) saturate(1.2)`;
    }
  },

  // Spring Physics Animation for Message Bubbles
  SpringMessage: {
    mounted() {
      this.el.classList.add('spring-in');
      setTimeout(() => this.el.classList.remove('spring-in'), 800);
    }
  },

  // Parallax on Message Bubbles
  ParallaxBubble: {
    mounted() {
      this.handleScroll = this.handleScroll.bind(this);
      window.addEventListener('scroll', this.handleScroll, { passive: true });
      this.handleScroll();
    },
    destroyed() {
      window.removeEventListener('scroll', this.handleScroll);
    },
    handleScroll() {
      const rect = this.el.getBoundingClientRect();
      const offset = rect.top / window.innerHeight;
      this.el.style.transform = `translateY(${offset * 12}px)`;
    }
  },

  // Particle Effect for Celebrations
  ParticleEffect: {
    mounted() {
      // Placeholder: trigger particles on custom event
      this.handleEvent('celebrate', () => this.showParticles());
    },
    showParticles() {
      // Simple confetti effect (placeholder)
      const container = document.createElement('div');
      container.className = 'particle-effect';
      for (let i = 0; i < 24; i++) {
        const dot = document.createElement('div');
        dot.style.position = 'absolute';
        dot.style.left = `${Math.random() * 100}%`;
        dot.style.top = `${Math.random() * 100}%`;
        dot.style.width = '8px';
        dot.style.height = '8px';
        dot.style.borderRadius = '50%';
        dot.style.background = `hsl(${Math.random() * 360}, 80%, 60%)`;
        dot.style.opacity = 0.8;
        dot.style.transform = `scale(${0.8 + Math.random() * 0.6})`;
        dot.style.transition = 'all 1.2s cubic-bezier(0.22, 1, 0.36, 1)';
        container.appendChild(dot);
        setTimeout(() => {
          dot.style.top = `${50 + Math.random() * 40 - 20}%`;
          dot.style.opacity = 0;
        }, 50);
      }
      this.el.appendChild(container);
      setTimeout(() => container.remove(), 1400);
    }
  },

  // Dynamic Theme Manager
  ThemeManager: {
    mounted() {
      this.applyTheme(window.localStorage.getItem('theme') || 'auto');
      window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', this.handleSystemTheme.bind(this));
      this.handleEvent('set_theme', ({theme, sentiment}) => this.applyTheme(theme, sentiment));
    },
    applyTheme(theme, sentiment) {
      // Save user preference
      if (theme) window.localStorage.setItem('theme', theme);
      // Sentiment-based theme (optional)
      if (sentiment) {
        // Example: change gradient mesh based on sentiment
        let mesh = '--gradient-mesh-1';
        if (sentiment === 'positive') mesh = '--gradient-mesh-2';
        if (sentiment === 'negative') mesh = '--gradient-mesh-3';
        document.body.style.setProperty('background', `var(${mesh})`);
      }
      // Dark/Light/Auto
      if (theme === 'dark' || (theme === 'auto' && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
        document.documentElement.classList.add('dark');
        document.documentElement.classList.remove('light');
      } else {
        document.documentElement.classList.add('light');
        document.documentElement.classList.remove('dark');
      }
      // Smooth transition
      document.documentElement.style.transition = 'background 0.7s, color 0.7s';
    },
    handleSystemTheme(e) {
      if ((window.localStorage.getItem('theme') || 'auto') === 'auto') {
        this.applyTheme('auto');
      }
    }
  }
}

// Predictive Text Hook
Hooks.PredictiveText = {
  mounted() {
    this.input = this.el.querySelector('textarea');
    this.suggestionBox = document.createElement('div');
    this.suggestionBox.className = 'predictive-suggestion';
    this.suggestionBox.style.position = 'absolute';
    this.suggestionBox.style.right = '16px';
    this.suggestionBox.style.bottom = '60px';
    this.suggestionBox.style.zIndex = '100';
    this.suggestionBox.style.background = 'rgba(255,255,255,0.95)';
    this.suggestionBox.style.borderRadius = '12px';
    this.suggestionBox.style.boxShadow = '0 2px 8px rgba(0,0,0,0.08)';
    this.suggestionBox.style.padding = '8px 16px';
    this.suggestionBox.style.fontSize = '1rem';
    this.suggestionBox.style.color = '#2563eb';
    this.suggestionBox.style.display = 'none';
    this.el.appendChild(this.suggestionBox);
    this.input.addEventListener('input', this.handleInput.bind(this));
    this.input.addEventListener('keydown', this.handleKeydown.bind(this));
  },
  handleInput(e) {
    const value = this.input.value;
    if (value.length > 2) {
      // Placeholder: fetch prediction (simulate)
      this.suggestion = value + '... (AI suggestion)';
      this.suggestionBox.textContent = this.suggestion;
      this.suggestionBox.style.display = 'block';
    } else {
      this.suggestionBox.style.display = 'none';
    }
  },
  handleKeydown(e) {
    if (e.key === 'Tab' && this.suggestionBox.style.display === 'block') {
      e.preventDefault();
      this.input.value = this.suggestion;
      this.suggestionBox.style.display = 'none';
    }
  }
};

// Context Bubble Hook
Hooks.ContextBubble = {
  mounted() {
    this.el.addEventListener('mouseover', this.showBubble.bind(this));
    this.el.addEventListener('mouseout', this.hideBubble.bind(this));
    this.bubble = document.createElement('div');
    this.bubble.className = 'context-bubble';
    this.bubble.style.position = 'absolute';
    this.bubble.style.left = '0';
    this.bubble.style.top = '-40px';
    this.bubble.style.background = 'rgba(59,130,246,0.95)';
    this.bubble.style.color = 'white';
    this.bubble.style.padding = '6px 14px';
    this.bubble.style.borderRadius = '10px';
    this.bubble.style.fontSize = '0.95rem';
    this.bubble.style.boxShadow = '0 2px 8px rgba(0,0,0,0.08)';
    this.bubble.style.display = 'none';
    this.el.appendChild(this.bubble);
  },
  showBubble(e) {
    // Placeholder: show explanation for complex term
    this.bubble.textContent = 'AI explanation for: ' + this.el.textContent;
    this.bubble.style.display = 'block';
  },
  hideBubble(e) {
    this.bubble.style.display = 'none';
  }
};

// Emotion Detection Hook
Hooks.EmotionDetection = {
  mounted() {
    // Placeholder: listen for emotion event
    this.handleEvent('emotion', ({sentiment}) => this.applyEmotion(sentiment));
  },
  applyEmotion(sentiment) {
    // Example: subtle UI adaptation
    if (sentiment === 'positive') {
      this.el.style.boxShadow = '0 0 0 4px #10B98144';
    } else if (sentiment === 'negative') {
      this.el.style.boxShadow = '0 0 0 4px #EF444444';
    } else {
      this.el.style.boxShadow = '';
    }
  }
};

// Code Block Syntax Highlighting (placeholder for Prism.js or similar)
Hooks.CodeBlock = {
  mounted() {
    // Placeholder: highlight code blocks
    if (window.Prism) {
      window.Prism.highlightAllUnder(this.el);
    }
  }
};

// Rich Media Preview (placeholder)
Hooks.RichMediaPreview = {
  mounted() {
    // Placeholder: show inline media preview
    // In production, parse message content and render previews
  }
};

// Collaborative Canvas (placeholder)
Hooks.CollaborativeCanvas = {
  mounted() {
    // Placeholder: initialize collaborative drawing/diagramming
    // In production, integrate with a canvas library
  }
};

// Thread Connector (placeholder)
Hooks.ThreadConnector = {
  mounted() {
    // Placeholder: draw visual connection lines for threads
  }
};

// Time Travel Slider (placeholder)
Hooks.TimeTravelSlider = {
  mounted() {
    // Placeholder: implement slider to navigate conversation history
  }
};

// 3D Tilt Effect Hook
Hooks.Tilt3D = {
  mounted() {
    this.el.addEventListener('mousemove', this.handleMove.bind(this));
    this.el.addEventListener('mouseleave', this.resetTilt.bind(this));
  },
  handleMove(e) {
    const rect = this.el.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const centerX = rect.width / 2;
    const centerY = rect.height / 2;
    const rotateY = ((x - centerX) / centerX) * 8;
    const rotateX = ((centerY - y) / centerY) * 2;
    this.el.style.transform = `perspective(600px) rotateY(${rotateY}deg) rotateX(${rotateX}deg) scale(1.04)`;
  },
  resetTilt() {
    this.el.style.transform = '';
  }
};

// Depth-based Organization Hook
Hooks.DepthImportant = {
  mounted() {
    this.el.classList.add('depth-important');
  }
};

// Magnetic Floating Action Button Hook
Hooks.FabMagnetic = {
  mounted() {
    this.el.addEventListener('mousemove', this.magnetize.bind(this));
    this.el.addEventListener('mouseleave', this.resetMagnet.bind(this));
  },
  magnetize(e) {
    const rect = this.el.getBoundingClientRect();
    const x = e.clientX - rect.left - rect.width / 2;
    const y = e.clientY - rect.top - rect.height / 2;
    this.el.style.transform = `translate(${x * 0.08}px, ${y * 0.08}px) scale(1.08)`;
  },
  resetMagnet() {
    this.el.style.transform = '';
  }
};

// 3D Emoji Reaction Hook
Hooks.Emoji3D = {
  mounted() {
    this.el.addEventListener('mouseenter', () => {
      this.el.style.transform = 'scale(1.4) translateY(-8px)';
      this.el.style.filter = 'drop-shadow(0 8px 16px rgba(59,130,246,0.18))';
    });
    this.el.addEventListener('mouseleave', () => {
      this.el.style.transform = '';
      this.el.style.filter = '';
    });
  }
};

// Skeleton Screen Hook for Progressive Loading
Hooks.SkeletonScreen = {
  mounted() {
    this.el.classList.add('skeleton-loading');
    setTimeout(() => this.el.classList.remove('skeleton-loading'), 1200); // Simulate loading
  }
};

// Register Service Worker for Offline Support (PWA)
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/service-worker.js').catch(() => {});
  });
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Collapsible Sidebar Hook
Hooks.CollapsibleSidebar = {
  mounted() {
    this.button = this.el.querySelector('.sidebar-toggle');
    if (this.button) {
      this.button.addEventListener('click', () => {
        this.el.classList.toggle('collapsed');
      });
    }
  }
};

// Picture-in-Picture Chat Hook
Hooks.PiPChat = {
  mounted() {
    // Placeholder: enable PiP mode for chat
  }
};

// Split Screen View Hook
Hooks.SplitScreen = {
  mounted() {
    // Placeholder: enable split-screen for comparing conversations
  }
};

// Mini Chat Widget Hook
Hooks.MiniChatWidget = {
  mounted() {
    // Placeholder: floating mini-chat for quick access
  }
};

// Conversation Map Hook
Hooks.ConversationMap = {
  mounted() {
    // Placeholder: visualize topic flow
  }
};

// Action Extraction Hook
Hooks.ActionExtraction = {
  mounted() {
    // Placeholder: extract and display action items
  }
};

// Sentiment Dashboard Hook
Hooks.SentimentDashboard = {
  mounted() {
    // Placeholder: show sentiment analysis charts
  }
};

// Smart Search Hook
Hooks.SmartSearch = {
  mounted() {
    // Placeholder: enable smart conversation search
  }
};

// User Layout Personalization Hook
Hooks.UserLayout = {
  mounted() {
    // Placeholder: adapt UI layout to user preferences
  }
};

// Custom Reactions Hook
Hooks.CustomReactions = {
  mounted() {
    // Placeholder: enable user-specific reaction sets
  }
};

// Quick Actions Hook
Hooks.QuickActions = {
  mounted() {
    // Placeholder: show personalized quick actions
  }
};

// AI Insights Hook
Hooks.AIInsights = {
  mounted() {
    // Placeholder: display AI-generated conversation insights
  }
};

// Live Collaboration Indicator Hook
Hooks.LiveCollabIndicator = {
  mounted() {
    // Placeholder: show live collaboration status
  }
};

// Shared Highlight Hook
Hooks.SharedHighlight = {
  mounted() {
    // Placeholder: enable shared annotations and highlights
  }
};

// Templates Marketplace Hook
Hooks.TemplatesMarketplace = {
  mounted() {
    // Placeholder: show conversation templates marketplace
  }
};

// Achievements Hook
Hooks.Achievements = {
  mounted() {
    // Placeholder: display achievement animations
  }
};

