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
import topbar from "../vendor/topbar"

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
  }
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

