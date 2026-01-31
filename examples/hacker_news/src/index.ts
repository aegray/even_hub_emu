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

type ListAction =
  | { type: 'prev' }
  | { type: 'next' }
  | { type: 'retry'; page: number }
  | { type: 'story'; storyIndex: number };

const HN_BASE = 'https://news.ycombinator.com/';
const HN_API = 'https://hn.algolia.com/api/v1/search';
const MAX_TEXT_CHARS = 2000;
const MAX_LIST_ITEMS = 20;
const MAX_ITEM_CHARS = 64;

const LIST_CONTAINER_ID = 1;
const TEXT_CONTAINER_ID = 2;

const bridge = await waitForEvenAppBridge();

let startupCreated = false;
let actionInFlight = false;

let currentPage = 1;
let currentStories: Story[] = [];
let currentActions: ListAction[] = [];

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

function parseHTML(html: string) {
  return new DOMParser().parseFromString(html, 'text/html');
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

async function ensureStartup() {
  if (startupCreated) {
    return;
  }

  const listContainer: ListContainerProperty = {
    xPosition: 0,
    yPosition: 0,
    width: 640,
    height: 250,
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
    yPosition: 250,
    width: 640,
    height: 100,
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
  const listContainer: ListContainerProperty = {
    xPosition: 0,
    yPosition: 0,
    width: 640,
    height: 250,
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
    yPosition: 250,
    width: 640,
    height: 100,
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
  const textContainer: TextContainerProperty = {
    xPosition: 0,
    yPosition: 250,
    width: 640,
    height: 100,
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

    const hint = 'Select a story. Use Prev/Next to change page.';
    await rebuildList(
      labels.length > 0 ? labels : ['Retry', 'Next page ▶'],
      labels.length > 0 ? `HN page ${page}. ${hint}` : 'No stories returned.'
    );
    if (labels.length === 0) {
      currentActions = [{ type: 'retry', page }, { type: 'next' }];
    }
  } catch (err) {
    await rebuildList(['Retry', 'Next page ▶'], 'Failed to load Hacker News.');
    currentActions = [{ type: 'retry', page }, { type: 'next' }];
  } finally {
    actionInFlight = false;
  }
}

bridge.onEvenHubEvent(async (event) => {
  if (!event.listEvent || actionInFlight) {
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

  const story = currentStories[action.storyIndex];
  if (story) {
    await updateText(formatStoryDetails(story));
  }
});

await loadPage(1);
