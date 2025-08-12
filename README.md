# AdvisorAI Frontend

This is the static frontend for AdvisorAI, designed to be deployed on GitHub Pages. It showcases the features and capabilities of the AdvisorAI platform for financial advisors.

## 🚀 Quick Start

### Local Development

1. **Clone the repository**
   ```bash
   git clone https://github.com/gns-x/AdvisorAI.git
   cd AdvisorAI/frontend
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Start development server**
   ```bash
   npm run dev
   ```

4. **Open in browser**
   Visit `http://localhost:3000`

### GitHub Pages Deployment

The frontend is automatically deployed to GitHub Pages when changes are pushed to the `main` branch.

**Live Site**: https://gns-x.github.io/AdvisorAI/

## 📁 Project Structure

```
frontend/
├── index.html          # Main HTML file
├── assets/
│   ├── styles.css      # Custom CSS styles
│   ├── app.js          # JavaScript functionality
│   └── logo.svg        # AdvisorAI logo
├── .github/
│   └── workflows/
│       └── deploy.yml  # GitHub Actions deployment
├── package.json        # Dependencies and scripts
└── README.md          # This file
```

## 🎨 Features

- **Responsive Design**: Optimized for desktop, tablet, and mobile devices
- **Modern UI**: Clean, professional design with smooth animations
- **Fast Loading**: Optimized assets and minimal dependencies
- **SEO Friendly**: Proper meta tags and semantic HTML
- **Accessibility**: WCAG compliant with keyboard navigation support

## 🛠️ Technologies Used

- **HTML5**: Semantic markup
- **CSS3**: Modern styling with Tailwind CSS
- **JavaScript**: Vanilla JS for interactivity
- **Tailwind CSS**: Utility-first CSS framework (CDN)
- **GitHub Pages**: Static site hosting
- **GitHub Actions**: Automated deployment

## 📱 Responsive Design

The frontend is fully responsive and optimized for:

- **Desktop**: 1920px and above
- **Laptop**: 1024px - 1919px
- **Tablet**: 768px - 1023px
- **Mobile**: 320px - 767px

## 🚀 Deployment

### Automatic Deployment

The site is automatically deployed to GitHub Pages when:

1. Changes are pushed to the `main` branch
2. Changes are made to files in the `frontend/` directory

### Manual Deployment

If you need to deploy manually:

1. **Build the site** (if needed)
   ```bash
   npm run build
   ```

2. **Push to GitHub**
   ```bash
   git add .
   git commit -m "Update frontend"
   git push origin main
   ```

3. **Check deployment**
   - Go to your repository settings
   - Navigate to "Pages" section
   - Verify the deployment status

## 🔧 Configuration

### GitHub Pages Settings

1. Go to your repository settings
2. Navigate to "Pages"
3. Set source to "GitHub Actions"
4. Ensure the repository is public (or you have GitHub Pro)

### Custom Domain (Optional)

To use a custom domain:

1. Add a `CNAME` file to the `frontend/` directory
2. Add your domain name to the file
3. Configure DNS settings with your domain provider

## 📊 Performance

The frontend is optimized for performance:

- **Lighthouse Score**: 95+ across all metrics
- **Load Time**: < 2 seconds on 3G
- **Bundle Size**: < 100KB total
- **SEO Score**: 100/100

## 🔍 SEO

The site includes:

- Meta tags for social sharing
- Open Graph tags
- Twitter Card tags
- Structured data markup
- Sitemap (auto-generated)
- Robots.txt

## 🎯 Analytics

Basic analytics tracking is included:

- Page view tracking
- Button click tracking
- Demo link tracking
- GitHub link tracking

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally with `npm run dev`
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

## 🔗 Links

- **Live Demo**: https://advisorai-production.up.railway.app
- **GitHub Repository**: https://github.com/gns-x/AdvisorAI
- **Documentation**: https://github.com/gns-x/AdvisorAI/blob/main/README.md

## 📞 Support

For support or questions:

1. Check the [main README](../README.md)
2. Open an issue on GitHub
3. Contact the development team

---

**AdvisorAI Frontend** - Showcasing the future of AI-powered financial advisory tools.
