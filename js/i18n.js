(function () {
  'use strict';

  var translations = {
    'Yocto 使用知识库': 'Yocto Knowledge Base',
    'Git 知识库': 'Git Knowledge Base',
    '知识库总览': 'Knowledge Base Overview',
    '黄色的森林分出两条路': 'Two roads diverged in a yellow wood',
    '我选择人迹更少的那一条，从此决定我一生的道路。': 'I took the one less traveled by, and that has made all the difference.',
    '阅读全文': 'Read more',
    '下一篇': 'Next',
    '上一篇': 'Previous',
    '本文标题': 'Title',
    '本文作者': 'Author',
    '创建时间': 'Created',
    '本文链接': 'Permalink',
    '版权声明': 'License',
    '访问人数': 'Visitors',
    '总访问量': 'Views',
    '由': 'Powered by',
    '知识库': 'Knowledge Base',
    '首页': 'Home',
    '归档': 'Archives',
    '分类': 'Categories',
    '标签': 'Tags',
    '关于': 'About',
    '百度': 'Baidu',
    '评论': 'Comments',
    '更新于': 'Updated',
    '搜索...': 'Search...',
    '知识库入口': 'Knowledge Base',
    '集中查阅 Git 与 Yocto 知识，按专题、流程和验证记录快速定位。': 'Browse Git and Yocto knowledge by topic, workflow, and verification record.',
    'Git 工作流、分支、提交和恢复': 'Git workflows, branches, commits, and recovery',
    'Yocto 构建、Layer、Recipe 和 devtool': 'Yocto builds, layers, recipes, and devtool',
    '进入知识库': 'Open Knowledge Base',
    '暂无文章': 'No posts yet',
    '查阅知识库': 'Browse the knowledge base',
    '知识库页面': 'Knowledge Base Page',
    '驱动': 'powered by',
    '主题': 'Theme',
    'about': 'About',
  };

  var englishPages = {
    '/knowledge-base/': '/knowledge-base/en/',
    '/knowledge-base/git/': '/knowledge-base/en/git/',
    '/knowledge-base/yocto/': '/knowledge-base/en/yocto/',
  };
  var chinesePages = {
    '/knowledge-base/en/': '/knowledge-base/',
    '/knowledge-base/en/git/': '/knowledge-base/git/',
    '/knowledge-base/en/yocto/': '/knowledge-base/yocto/',
  };

  function getStoredLanguage() {
    try {
      return window.localStorage.getItem('blog-language');
    } catch (error) {
      return null;
    }
  }

  function setStoredLanguage(language) {
    try {
      window.localStorage.setItem('blog-language', language);
    } catch (error) {
      // Storage can be disabled without affecting the page switcher.
    }
  }

  function translateText(text) {
    var result = text;
    Object.keys(translations).sort(function (a, b) { return b.length - a.length; }).forEach(function (source) {
      result = result.split(source).join(translations[source]);
    });
    return result;
  }

  function pageLanguage() {
    var path = window.location.pathname.replace(/index\.html$/, '');
    if (englishPages[path]) return 'zh';
    if (path.indexOf('/knowledge-base/en/') === 0) return 'en';
    return getStoredLanguage() === 'en' ? 'en' : 'zh';
  }

  function setTitle(language) {
    if (!document.title) return;
    var title = document.title;
    if (language === 'en') {
      title = translateText(title).replace('使用', ' ').replace('知识库', 'Knowledge Base');
    } else {
      title = title.replace('Yocto Knowledge Base', 'Yocto 使用知识库')
        .replace('Git Knowledge Base', 'Git 知识库')
        .replace('Knowledge Base', '知识库');
    }
    document.title = title;
  }

  function addSwitchers() {
    var lists = document.querySelectorAll('.menu-list, .drawer-menu-list');
    lists.forEach(function (list) {
      if (list.querySelector('[data-language-toggle]')) return;
      var item = document.createElement('li');
      item.className = list.classList.contains('menu-list') ? 'menu-item language-switcher' : 'drawer-menu-item flex-center language-switcher';
      var button = document.createElement('button');
      button.type = 'button';
      button.setAttribute('data-language-toggle', '');
      item.appendChild(button);
      list.appendChild(item);
    });
  }

  function collectTextNodes() {
    var nodes = [];
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    var node;
    while ((node = walker.nextNode())) {
      if (node.parentElement && !node.parentElement.closest('pre, code, script, style, [data-no-i18n]')) {
        nodes.push({ node: node, original: node.nodeValue });
      }
    }
    return nodes;
  }

  function applyLanguage(language, nodes) {
    document.documentElement.lang = language === 'en' ? 'en' : 'zh-CN';
    document.body.classList.toggle('language-en', language === 'en');
    nodes.forEach(function (item) {
      item.node.nodeValue = language === 'en' ? translateText(item.original) : item.original;
    });
    document.querySelectorAll('[placeholder]').forEach(function (input) {
      if (!input.dataset.originalPlaceholder) input.dataset.originalPlaceholder = input.getAttribute('placeholder');
      input.setAttribute('placeholder', language === 'en' ? translateText(input.dataset.originalPlaceholder) : input.dataset.originalPlaceholder);
    });
    document.querySelectorAll('[data-language-toggle]').forEach(function (button) {
      button.textContent = language === 'en' ? '中文' : 'English';
      button.setAttribute('aria-label', language === 'en' ? 'Switch to Chinese' : 'Switch to English');
    });
    document.querySelectorAll('[data-zh-href][data-en-href]').forEach(function (link) {
      link.setAttribute('href', language === 'en' ? link.dataset.enHref : link.dataset.zhHref);
    });
    setTitle(language);
  }

  function switchLanguage(current, nodes) {
    var path = window.location.pathname.replace(/index\.html$/, '');
    var target = current === 'en' ? chinesePages[path] : englishPages[path];
    if (target) {
      setStoredLanguage(current === 'en' ? 'zh' : 'en');
      window.location.href = target;
      return;
    }
    var next = current === 'en' ? 'zh' : 'en';
    setStoredLanguage(next);
    applyLanguage(next, nodes);
  }

  function init() {
    addSwitchers();
    var nodes = collectTextNodes();
    var language = pageLanguage();
    document.querySelectorAll('[data-language-toggle]').forEach(function (button) {
      button.addEventListener('click', function () { switchLanguage(language, nodes); language = language === 'en' ? 'zh' : 'en'; });
    });
    applyLanguage(language, nodes);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
}());
