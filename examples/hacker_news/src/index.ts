import {
  waitForEvenAppBridge,
  ListContainerProperty,
  TextContainerProperty,
  OsEventTypeList,
} from '@evenrealities/even_hub_sdk';

type Story = {
  id: string;
  title: string;
  url: string;
  score?: number;
  by?: string;
  comments?: number;
  age?: string;
};

type CommentItem = {
  id: string;
  author?: string;
  text: string;
  age?: string;
  depth: number;
};

type ListAction =
  | { type: 'prev' }
  | { type: 'next' }
  | { type: 'retry'; page: number }
  | { type: 'story'; storyIndex: number }
  | { type: 'comment'; commentIndex: number }
  | { type: 'commentPrev' }
  | { type: 'commentNext' };

const HN_BASE = 'https://news.ycombinator.com/';
const HN_API = 'https://hn.algolia.com/api/v1/search';
const HN_ITEM_API = 'https://hn.algolia.com/api/v1/items';
const MAX_TEXT_CHARS = 2000;
const MAX_LIST_ITEMS = 20;
const MAX_ITEM_CHARS = 64;
const MAX_COMMENT_INDENT = 4;
const LIST_HEIGHT_DEFAULT = 250;
const TEXT_HEIGHT_DEFAULT = 100;
const TOTAL_HEIGHT = 350;
const LIST_HEIGHT_EXPANDED = 175;
const TEXT_HEIGHT_EXPANDED = 175;

const LIST_CONTAINER_ID = 1;
const TEXT_CONTAINER_ID = 2;

const bridge = await waitForEvenAppBridge();

let startupCreated = false;
let actionInFlight = false;

let currentPage = 1;
let currentStories: Story[] = [];
let currentActions: ListAction[] = [];
let currentComments: CommentItem[] = [];
let currentView: 'list' | 'story' = 'list';
let currentStory: Story | null = null;
let currentCommentPage = 1;
let currentLabels: string[] = [];
let currentLayout: 'default' | 'expanded' = 'default';

let listCache: {
  labels: string[];
  actions: ListAction[];
  text: string;
  page: number;
  stories: Story[];
} | null = null;

function normalizeText(text: string) {
  const cleaned = text.replace(/\s+/g, ' ').trim();
  if (cleaned.length <= MAX_TEXT_CHARS) {
    return cleaned;
  }
  return cleaned.slice(0, MAX_TEXT_CHARS - 3) + '...';
}

function truncateTitle(text: string, max = 60) {
  const cleaned = text.replace(/\s+/g, ' ').trim();
  if (cleaned.length <= max) {
    return cleaned;
  }
  return cleaned.slice(0, max - 3) + '...';
}

function clampLabel(text: string) {
  const cleaned = text.replace(/\s+/g, ' ').trim();
  if (cleaned.length <= MAX_ITEM_CHARS) {
    return cleaned;
  }
  return cleaned.slice(0, MAX_ITEM_CHARS - 3) + '...';
}

function clampLabelLoose(text: string) {
  if (text.length <= MAX_ITEM_CHARS) {
    return text;
  }
  return text.slice(0, MAX_ITEM_CHARS - 3) + '...';
}

function getLayoutHeights(layout: 'default' | 'expanded') {
  if (layout === 'expanded') {
    return { listHeight: LIST_HEIGHT_EXPANDED, textHeight: TEXT_HEIGHT_EXPANDED };
  }
  return { listHeight: LIST_HEIGHT_DEFAULT, textHeight: TEXT_HEIGHT_DEFAULT };
}

function setLayout(layout: 'default' | 'expanded') {
  currentLayout = layout;
}

function formatCommentLabel(comment: CommentItem) {
  const depth = Math.min(comment.depth, MAX_COMMENT_INDENT);
  const indent = depth > 0 ? `${'>'.repeat(depth)} ` : '';
  const author = comment.author ? `${comment.author}: ` : '';
  const text = comment.text.replace(/\s+/g, ' ').trim() || '[comment]';
  return clampLabelLoose(`${indent}${author}${text}`);
}

function getCommentPagination(comments: CommentItem[]) {
  if (comments.length <= MAX_LIST_ITEMS) {
    return {
      paginated: false,
      slots: MAX_LIST_ITEMS,
      totalPages: 1,
    };
  }
  const slots = Math.max(1, MAX_LIST_ITEMS - 2);
  return {
    paginated: true,
    slots,
    totalPages: Math.max(1, Math.ceil(comments.length / slots)),
  };
}

function parseHTML(html: string) {
  return new DOMParser().parseFromString(html, 'text/html');
}

function htmlToText(html: string) {
  const doc = parseHTML(`<div>${html}</div>`);
  return doc.body.textContent?.replace(/\s+/g, ' ').trim() || '';
}

function resolveStoryUrl(storyId: string, rawUrl: string | null) {
  if (rawUrl && rawUrl.trim()) {
    return rawUrl.trim();
  }
  return new URL(`item?id=${storyId}`, HN_BASE).toString();
}

function parseScore(text: string) {
  const match = text.match(/(\d+)/);
  return match ? Number(match[1]) : undefined;
}

function parseComments(text: string) {
  const match = text.match(/(\d+)/);
  return match ? Number(match[1]) : undefined;
}

function parseStoriesFromHtml(html: string): Story[] {
  const doc = parseHTML(html);
  const rows = Array.from(doc.querySelectorAll('tr.athing'));
  const stories: Story[] = [];

  for (const row of rows) {
    const id = row.getAttribute('id') || '';
    const titleLink =
      (row.querySelector('.titleline > a') as HTMLAnchorElement | null) ||
      (row.querySelector('a.storylink') as HTMLAnchorElement | null) ||
      (row.querySelector('td.title a') as HTMLAnchorElement | null);
    if (!titleLink) {
      continue;
    }
    const title = titleLink.textContent?.trim() || 'Untitled';
    const href = titleLink.getAttribute('href') || '';
    const url = resolveStoryUrl(id, new URL(href, HN_BASE).toString());

    const subtext =
      (row.nextElementSibling?.querySelector('.subtext') as HTMLElement | null) ||
      (row.parentElement?.querySelector(`tr#${id} + tr .subtext`) as HTMLElement | null);
    const scoreText = subtext?.querySelector('.score')?.textContent?.trim() || '';
    const score = scoreText ? parseScore(scoreText) : undefined;
    const by = subtext?.querySelector('.hnuser')?.textContent?.trim() || undefined;
    const age = subtext?.querySelector('.age')?.textContent?.trim() || undefined;
    let comments: number | undefined;
    const subLinks = Array.from(subtext?.querySelectorAll('a') ?? []);
    for (const link of subLinks) {
      const text = link.textContent?.trim() || '';
      if (/comment|discuss/i.test(text)) {
        comments = parseComments(text) ?? 0;
      }
    }

    stories.push({ id, title, url, score, by, comments, age });
  }

  return stories;
}

async function fetchFrontPageFromHtml(page: number): Promise<Story[]> {
  const url = new URL('news', HN_BASE);
  if (page > 1) {
    url.searchParams.set('p', String(page));
  }
  const response = await fetch(url.toString(), { redirect: 'follow' });
  if (!response.ok) {
    throw new Error(`HN HTML error: ${response.status}`);
  }
  const html = await response.text();
  return parseStoriesFromHtml(html);
}

async function fetchFrontPageFromApi(page: number): Promise<Story[]> {
  const apiUrl = new URL(HN_API);
  apiUrl.searchParams.set('tags', 'front_page');
  apiUrl.searchParams.set('page', String(Math.max(0, page - 1)));
  apiUrl.searchParams.set('hitsPerPage', '30');

  const response = await fetch(apiUrl.toString(), { redirect: 'follow' });
  if (!response.ok) {
    throw new Error(`HN API error: ${response.status}`);
  }
  const data = (await response.json()) as {
    hits: Array<{
      objectID: string;
      title: string | null;
      url: string | null;
      points: number | null;
      author: string | null;
      num_comments: number | null;
      created_at: string | null;
    }>;
  };

  return data.hits.map((hit) => ({
    id: hit.objectID,
    title: hit.title?.trim() || 'Untitled',
    url: resolveStoryUrl(hit.objectID, hit.url),
    score: hit.points ?? undefined,
    by: hit.author ?? undefined,
    comments: hit.num_comments ?? undefined,
    age: hit.created_at ? new Date(hit.created_at).toLocaleDateString() : undefined,
  }));
}

async function fetchFrontPage(page: number): Promise<Story[]> {
  const stories = await fetchFrontPageFromHtml(page);
  if (stories.length > 0) {
    return stories;
  }
  return await fetchFrontPageFromApi(page);
}

async function fetchStoryPageSummary(story: Story) {
  try {
    const response = await fetch(story.url, { redirect: 'follow' });
    if (!response.ok) {
      return '';
    }
    const contentType = response.headers.get('content-type') ?? '';
    if (!contentType.includes('text/html')) {
      return '';
    }
    const html = await response.text();
    const doc = parseHTML(html);
    const title = doc.querySelector('title')?.textContent?.trim() || '';
    const description =
      doc.querySelector('meta[name="description"]')?.getAttribute('content')?.trim() || '';
    const parts = [];
    if (title) {
      parts.push(`Page: ${title}`);
    }
    if (description) {
      parts.push(description);
    }
    return parts.join('\n');
  } catch {
    return '';
  }
}

async function fetchStoryComments(storyId: string): Promise<CommentItem[]> {
  const apiUrl = new URL(`${HN_ITEM_API}/${storyId}`);
  const response = await fetch(apiUrl.toString(), { redirect: 'follow' });
  if (!response.ok) {
    throw new Error(`HN item API error: ${response.status}`);
  }
  const data = (await response.json()) as {
    id: number | string;
    children?: Array<{
      id: number | string;
      author?: string | null;
      text?: string | null;
      created_at?: string | null;
      children?: unknown[];
    }>;
  };

  const comments: CommentItem[] = [];

  const collect = (nodes: Array<any>, depth: number) => {
    for (const node of nodes) {
      if (!node) {
        continue;
      }
      const rawText = typeof node.text === 'string' ? node.text : '';
      const text = htmlToText(rawText);
      const author = typeof node.author === 'string' ? node.author : undefined;
      const age = node.created_at ? new Date(node.created_at).toLocaleDateString() : undefined;
      comments.push({
        id: String(node.id ?? ''),
        author,
        text: text || '[comment deleted]',
        age,
        depth,
      });
      const children = Array.isArray(node.children) ? node.children : [];
      if (children.length > 0) {
        collect(children, depth + 1);
      }
    }
  };

  const rootChildren = Array.isArray(data.children) ? data.children : [];
  collect(rootChildren, 0);
  return comments;
}

function buildList(stories: Story[], page: number) {
  const labels: string[] = [];
  const actions: ListAction[] = [];

  const hasPrev = page > 1;
  const reserved = (hasPrev ? 1 : 0) + 1;
  const storySlots = Math.max(0, MAX_LIST_ITEMS - reserved);
  const visibleStories = stories.slice(0, storySlots);

  if (hasPrev) {
    labels.push('◀ Prev page');
    actions.push({ type: 'prev' });
  }

  visibleStories.forEach((story, index) => {
    const title = clampLabel(`${index + 1}. ${truncateTitle(story.title)}`) || `${index + 1}. Untitled`;
    labels.push(title);
    actions.push({ type: 'story', storyIndex: index });
  });

  labels.push('Next page ▶');
  actions.push({ type: 'next' });

  return { labels, actions };
}

function buildCommentList(comments: CommentItem[], page: number) {
  if (comments.length === 0) {
    return {
      labels: ['No comments yet.'],
      actions: [{ type: 'comment', commentIndex: -1 } as ListAction],
      totalPages: 1,
    };
  }

  const { paginated, slots, totalPages } = getCommentPagination(comments);
  const safePage = Math.min(Math.max(1, page), totalPages);

  const start = (safePage - 1) * slots;
  const end = start + slots;
  const visible = comments.slice(start, end);

  const labels: string[] = [];
  const actions: ListAction[] = [];

  if (paginated && safePage > 1) {
    labels.push('◀ Previous comments');
    actions.push({ type: 'commentPrev' });
  }

  visible.forEach((comment, index) => {
    labels.push(formatCommentLabel(comment));
    actions.push({ type: 'comment', commentIndex: start + index });
  });

  if (paginated && safePage < totalPages) {
    labels.push('More comments ▶');
    actions.push({ type: 'commentNext' });
  }

  return { labels, actions, totalPages };
}

async function ensureStartup() {
  if (startupCreated) {
    return;
  }

  const { listHeight, textHeight } = getLayoutHeights('default');
  const listContainer: ListContainerProperty = {
    xPosition: 0,
    yPosition: 0,
    width: 640,
    height: listHeight,
    containerID: LIST_CONTAINER_ID,
    containerName: 'hn-list',
    itemContainer: {
      itemCount: 1,
      itemWidth: 0,
      isItemSelectBorderEn: 1,
      itemName: ['Loading...'],
    },
    isEventCapture: 1,
  };

  const textContainer: TextContainerProperty = {
    xPosition: 0,
    yPosition: listHeight,
    width: 640,
    height: textHeight,
    containerID: TEXT_CONTAINER_ID,
    containerName: 'hn-text',
    content: 'Hacker News reader',
    isEventCapture: 0,
  };

  const result = await bridge.createStartUpPageContainer({
    containerTotalNum: 2,
    listObject: [listContainer],
    textObject: [textContainer],
  });

  startupCreated = result === 0;
}

async function rebuildList(labels: string[], text: string) {
  await ensureStartup();
  const safeLabels = labels.map((label, index) => (label && label.trim().length > 0 ? label : `${index + 1}. Untitled`));
  currentLabels = safeLabels;
  const { listHeight, textHeight } = getLayoutHeights(currentLayout);
  const listContainer: ListContainerProperty = {
    xPosition: 0,
    yPosition: 0,
    width: 640,
    height: listHeight,
    containerID: LIST_CONTAINER_ID,
    containerName: 'hn-list',
    itemContainer: {
      itemCount: Math.max(1, safeLabels.length),
      itemWidth: 0,
      isItemSelectBorderEn: 1,
      itemName: safeLabels.length > 0 ? safeLabels : ['No stories'],
    },
    isEventCapture: 1,
  };

  const textContainer: TextContainerProperty = {
    xPosition: 0,
    yPosition: listHeight,
    width: 640,
    height: textHeight,
    containerID: TEXT_CONTAINER_ID,
    containerName: 'hn-text',
    content: normalizeText(text),
    isEventCapture: 0,
  };

  await bridge.rebuildPageContainer({
    containerTotalNum: 2,
    listObject: [listContainer],
    textObject: [textContainer],
  });
}

async function updateText(text: string) {
  const { listHeight, textHeight } = getLayoutHeights(currentLayout);
  const textContainer: TextContainerProperty = {
    xPosition: 0,
    yPosition: listHeight,
    width: 640,
    height: textHeight,
    containerID: TEXT_CONTAINER_ID,
    containerName: 'hn-text',
    content: normalizeText(text),
    isEventCapture: 0,
  };
  await bridge.textContainerUpgrade(textContainer);
}

function formatStoryDetails(story: Story) {
  const metaParts: string[] = [];
  if (typeof story.score === 'number') {
    metaParts.push(`${story.score} points`);
  }
  if (story.by) {
    metaParts.push(`by ${story.by}`);
  }
  if (typeof story.comments === 'number') {
    metaParts.push(`${story.comments} comments`);
  }
  if (story.age) {
    metaParts.push(story.age);
  }
  const meta = metaParts.join(' · ');
  return [story.title, story.url, meta].filter(Boolean).join('\n');
}

function formatCommentDetails(comment: CommentItem) {
  const metaParts: string[] = [];
  if (comment.author) {
    metaParts.push(`by ${comment.author}`);
  }
  if (comment.age) {
    metaParts.push(comment.age);
  }
  const meta = metaParts.join(' · ');
  return [meta, comment.text].filter(Boolean).join('\n');
}

async function showListView() {
  if (actionInFlight) {
    return;
  }
  actionInFlight = true;
  try {
    if (!listCache) {
      actionInFlight = false;
      await loadPage(1);
      return;
    }
    currentView = 'list';
    currentPage = listCache.page;
    currentStories = listCache.stories;
    currentActions = listCache.actions;
    currentComments = [];
    currentStory = null;
    currentCommentPage = 1;
    setLayout('default');
    await rebuildList(listCache.labels, listCache.text);
  } finally {
    actionInFlight = false;
  }
}

async function showStoryView(story: Story) {
  if (actionInFlight) {
    return;
  }
  actionInFlight = true;
  try {
    currentView = 'story';
    currentStory = story;
    currentComments = [];
    currentCommentPage = 1;
    setLayout('expanded');
    await updateText(`Loading "${story.title}"...`);

    const [commentsResult, pageResult] = await Promise.allSettled([
      fetchStoryComments(story.id),
      fetchStoryPageSummary(story),
    ]);

    const comments =
      commentsResult.status === 'fulfilled' ? commentsResult.value : [];
    const pageSummary =
      pageResult.status === 'fulfilled' ? pageResult.value : '';
    currentComments = comments;

    const { labels, actions, totalPages } = buildCommentList(comments, currentCommentPage);
    currentActions = actions;
    await rebuildList(labels, [
      formatStoryDetails(story),
      pageSummary,
      `Comments page ${currentCommentPage}/${totalPages}.`,
      'Double click to go back.',
    ]
      .filter(Boolean)
      .join('\n'));
  } finally {
    actionInFlight = false;
  }
}

async function showCommentPage(page: number) {
  if (actionInFlight || currentView !== 'story' || !currentStory) {
    return;
  }
  actionInFlight = true;
  try {
    setLayout('expanded');
    const { totalPages } = getCommentPagination(currentComments);
    const safePage = Math.min(Math.max(1, page), totalPages);
    currentCommentPage = safePage;

    const { labels, actions } = buildCommentList(currentComments, safePage);
    currentActions = actions;
    await rebuildList(labels, [
      formatStoryDetails(currentStory),
      `Comments page ${safePage}/${totalPages}.`,
      'Double click to go back.',
    ]
      .filter(Boolean)
      .join('\n'));
  } finally {
    actionInFlight = false;
  }
}

async function loadPage(page: number) {
  if (actionInFlight) {
    return;
  }
  actionInFlight = true;
  try {
    await ensureStartup();
    await updateText(`Loading page ${page}...`);
    const stories = await fetchFrontPage(page);
    //console.log('[HN] Loaded stories:', stories);
    const { labels, actions } = buildList(stories, page);
    //console.log('[HN] List labels:', labels);
    currentPage = page;
    currentStories = stories;
    currentActions = actions;
    currentView = 'list';
    currentStory = null;
    currentCommentPage = 1;
    setLayout('default');

    const hint = 'Select a story. Use Prev/Next to change page.';
    const listText = labels.length > 0 ? `HN page ${page}. ${hint}` : 'No stories returned.';
    await rebuildList(labels.length > 0 ? labels : ['Retry', 'Next page ▶'], listText);
    if (labels.length === 0) {
      currentActions = [{ type: 'retry', page }, { type: 'next' }];
    }
    listCache = {
      labels: labels.length > 0 ? labels : ['Retry', 'Next page ▶'],
      actions: currentActions,
      text: listText,
      page,
      stories,
    };
  } catch (err) {
    await rebuildList(['Retry', 'Next page ▶'], 'Failed to load Hacker News.');
    currentActions = [{ type: 'retry', page }, { type: 'next' }];
    currentView = 'list';
    currentStory = null;
    currentCommentPage = 1;
    setLayout('default');
    listCache = {
      labels: ['Retry', 'Next page ▶'],
      actions: currentActions,
      text: 'Failed to load Hacker News.',
      page,
      stories: [],
    };
  } finally {
    actionInFlight = false;
  }
}

bridge.onEvenHubEvent(async (event) => {
  if (!event.listEvent || actionInFlight) {
    return;
  }
  if (event.listEvent.eventType === OsEventTypeList.DOUBLE_CLICK_EVENT) {
    if (currentView === 'story') {
      await showListView();
    }
    return;
  }
  if (event.listEvent.eventType != OsEventTypeList.CLICK_EVENT) {
    return;
  }
  const rawIndex = event.listEvent.currentSelectItemIndex ?? 0;
  const index =
    rawIndex >= 0 && rawIndex < currentActions.length
      ? rawIndex
      : rawIndex - 1 >= 0 && rawIndex - 1 < currentActions.length
        ? rawIndex - 1
        : 0;
  const action = currentActions[index];
  //console.log("List action: ", action)
  if (!action) {
    return;
  }
  if (action.type === 'prev') {
    const prevPage = Math.max(1, currentPage - 1);
    if (prevPage !== currentPage) {
      await loadPage(prevPage);
    }
    return;
  }
  if (action.type === 'next') {
    await loadPage(currentPage + 1);
    return;
  }
  if (action.type === 'retry') {
    await loadPage(action.page);
    return;
  }
  if (action.type === 'story') {
    const story = currentStories[action.storyIndex];
    if (story) {
      await showStoryView(story);
    }
    return;
  }
  if (action.type === 'comment') {
    if (action.commentIndex < 0) {
      return;
    }
    const comment = currentComments[action.commentIndex];
    if (comment) {
      await updateText(formatCommentDetails(comment));
    }
    return;
  }
  if (action.type === 'commentPrev') {
    await showCommentPage(currentCommentPage - 1);
    return;
  }
  if (action.type === 'commentNext') {
    await showCommentPage(currentCommentPage + 1);
    return;
  }
});

await loadPage(1);
