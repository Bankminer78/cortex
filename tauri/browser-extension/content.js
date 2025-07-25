// Content script for Cortex Accountability Extension
// Extracts UI information and monitors user activity on web pages

class ActivityMonitor {
  constructor() {
    this.isMonitoring = true;
    this.lastActivity = null;
    this.activityBuffer = [];
    this.domain = window.location.hostname;
    
    this.init();
  }
  
  init() {
    console.log('Cortex Activity Monitor initialized on:', this.domain);
    
    // Listen for messages from background script
    chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
      if (message.type === 'monitoring_toggled') {
        this.isMonitoring = message.enabled;
        console.log('Monitoring toggled:', this.isMonitoring);
      }
    });
    
    // Start monitoring when page is fully loaded
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', () => this.startMonitoring());
    } else {
      this.startMonitoring();
    }
  }
  
  startMonitoring() {
    if (!this.isMonitoring) return;
    
    // Initial page analysis
    this.analyzeCurrentPage();
    
    // Monitor user interactions
    this.setupEventListeners();
    
    // Periodic checks for dynamic content
    setInterval(() => {
      if (this.isMonitoring) {
        this.analyzeCurrentPage();
      }
    }, 5000);
  }
  
  setupEventListeners() {
    // Monitor scrolling
    let scrollTimeout;
    window.addEventListener('scroll', () => {
      if (!this.isMonitoring) return;
      
      clearTimeout(scrollTimeout);
      scrollTimeout = setTimeout(() => {
        this.detectScrollingActivity();
      }, 500);
    });
    
    // Monitor clicks
    document.addEventListener('click', (event) => {
      if (!this.isMonitoring) return;
      this.detectClickActivity(event);
    });
    
    // Monitor form inputs
    document.addEventListener('input', (event) => {
      if (!this.isMonitoring) return;
      this.detectInputActivity(event);
    });
    
    // Monitor video play/pause
    document.addEventListener('play', (event) => {
      if (!this.isMonitoring) return;
      this.detectVideoActivity('play', event);
    }, true);
    
    document.addEventListener('pause', (event) => {
      if (!this.isMonitoring) return;
      this.detectVideoActivity('pause', event);
    }, true);
  }
  
  analyzeCurrentPage() {
    const pageInfo = this.extractPageInfo();
    const activity = this.classifyActivity(pageInfo);
    
    if (activity !== this.lastActivity) {
      this.reportActivity(activity, pageInfo);
      this.lastActivity = activity;
    }
  }
  
  extractPageInfo() {
    const info = {
      domain: this.domain,
      url: window.location.href,
      title: document.title,
      pathname: window.location.pathname,
      search: window.location.search,
      elements: this.extractUIElements()
    };
    
    return info;
  }
  
  extractUIElements() {
    const elements = {
      headings: [],
      buttons: [],
      links: [],
      videos: [],
      images: [],
      forms: []
    };
    
    // Extract headings
    document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(h => {
      if (h.textContent.trim()) {
        elements.headings.push(h.textContent.trim().substring(0, 100));
      }
    });
    
    // Extract visible buttons
    document.querySelectorAll('button, input[type=\"button\"], input[type=\"submit\"]').forEach(btn => {
      if (this.isElementVisible(btn) && btn.textContent.trim()) {
        elements.buttons.push(btn.textContent.trim().substring(0, 50));
      }
    });
    
    // Extract navigation links
    document.querySelectorAll('a[href]').forEach(link => {
      if (this.isElementVisible(link) && link.textContent.trim()) {
        elements.links.push({
          text: link.textContent.trim().substring(0, 50),
          href: link.href
        });
      }
    });
    
    // Extract video elements
    document.querySelectorAll('video').forEach(video => {
      if (this.isElementVisible(video)) {
        elements.videos.push({
          src: video.src || video.currentSrc,
          duration: video.duration,
          currentTime: video.currentTime,
          paused: video.paused
        });
      }
    });
    
    // Extract form elements
    document.querySelectorAll('form').forEach(form => {
      if (this.isElementVisible(form)) {
        elements.forms.push({
          action: form.action,
          method: form.method,
          inputs: Array.from(form.querySelectorAll('input, textarea, select')).length
        });
      }
    });
    
    return elements;
  }
  
  classifyActivity(pageInfo) {
    const domain = pageInfo.domain.toLowerCase();
    const url = pageInfo.url.toLowerCase();
    const title = pageInfo.title.toLowerCase();
    const pathname = pageInfo.pathname.toLowerCase();
    
    // Social media platforms
    if (domain.includes('instagram.com')) {
      if (pathname.includes('/direct/') || url.includes('direct')) {
        return 'messaging_instagram';
      } else if (pathname.includes('/stories/') || url.includes('stories')) {
        return 'viewing_stories_instagram';
      } else {
        return 'scrolling_instagram';
      }
    }
    
    if (domain.includes('youtube.com')) {
      if (pathname.includes('/watch')) {
        // Try to determine if it's music
        if (title.includes('music') || title.includes('song') || title.includes('album') ||
            url.includes('music') || pageInfo.elements.headings.some(h => 
              h.toLowerCase().includes('music') || h.toLowerCase().includes('song'))) {
          return 'watching_music';
        } else {
          return 'watching_videos';
        }
      } else {
        return 'browsing_youtube';
      }
    }
    
    if (domain.includes('reddit.com')) {
      if (pathname.includes('/r/machinelearning') || pathname.includes('/r/MachineLearning')) {
        return 'browsing_machine_learning';
      } else {
        return 'browsing_other_subreddits';
      }
    }
    
    if (domain.includes('twitter.com') || domain.includes('x.com')) {
      return 'browsing_twitter';
    }
    
    if (domain.includes('facebook.com')) {
      if (pathname.includes('/messages/') || url.includes('messenger')) {
        return 'messaging_facebook';
      } else {
        return 'scrolling_facebook';
      }
    }
    
    if (domain.includes('tiktok.com')) {
      return 'scrolling_tiktok';
    }
    
    // Shopping sites
    if (domain.includes('amazon.com') || domain.includes('ebay.com') || 
        domain.includes('target.com') || domain.includes('walmart.com') ||
        domain.includes('shop') || title.includes('cart') || 
        pageInfo.elements.buttons.some(btn => btn.toLowerCase().includes('add to cart'))) {
      return 'shopping_browsing';
    }
    
    // Work/productivity sites
    if (domain.includes('github.com') || domain.includes('stackoverflow.com') ||
        domain.includes('notion.so') || domain.includes('google.com/docs') ||
        domain.includes('office.com') || domain.includes('slack.com')) {
      return 'productive_work';
    }
    
    // Default classification
    return 'general_browsing';
  }
  
  detectScrollingActivity() {
    const scrollPosition = window.scrollY;
    const scrollHeight = document.documentElement.scrollHeight;
    const windowHeight = window.innerHeight;
    const scrollPercent = (scrollPosition / (scrollHeight - windowHeight)) * 100;
    
    this.reportActivity('scrolling', {
      domain: this.domain,
      scrollPercent: Math.round(scrollPercent),
      url: window.location.href
    });
  }
  
  detectClickActivity(event) {
    const target = event.target;
    const elementInfo = {
      tagName: target.tagName,
      className: target.className,
      textContent: target.textContent?.substring(0, 50),
      href: target.href
    };
    
    this.reportActivity('click', {
      domain: this.domain,
      element: elementInfo,
      url: window.location.href
    });
  }
  
  detectInputActivity(event) {
    const target = event.target;
    const inputInfo = {
      type: target.type,
      name: target.name,
      placeholder: target.placeholder,
      formAction: target.form?.action
    };
    
    this.reportActivity('input', {
      domain: this.domain,
      input: inputInfo,
      url: window.location.href
    });
  }
  
  detectVideoActivity(action, event) {
    const video = event.target;
    const videoInfo = {
      src: video.src || video.currentSrc,
      duration: video.duration,
      currentTime: video.currentTime,
      action: action
    };
    
    this.reportActivity('video_' + action, {
      domain: this.domain,
      video: videoInfo,
      url: window.location.href
    });
  }
  
  reportActivity(activityType, data) {
    // Send to background script
    chrome.runtime.sendMessage({
      type: 'page_activity',
      data: {
        activity: activityType,
        ...data,
        timestamp: Date.now()
      }
    }).catch(error => {
      console.error('Failed to send activity to background:', error);
    });
  }
  
  isElementVisible(element) {
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && 
           rect.top >= 0 && rect.top < window.innerHeight;
  }
}

// Initialize the activity monitor
const monitor = new ActivityMonitor();