(function() {
    // Check if a theme preference is already stored
    var storedTheme = window.localStorage.getItem('documenter-theme');
    
    // If no theme is stored, set the default to dark
    if (!storedTheme) {
        var defaultTheme = 'documenter-dark';
        window.localStorage.setItem('documenter-theme', defaultTheme);
        
        // Apply the theme immediately to avoid flashing
        document.documentElement.setAttribute('data-theme', defaultTheme);
    }
})();
