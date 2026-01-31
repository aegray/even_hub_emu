import {
  waitForEvenAppBridge,
  ListContainerProperty,
  TextContainerProperty,
  DeviceConnectType,
} from '@evenrealities/even_hub_sdk';


const bridge = await waitForEvenAppBridge();


function registerButtonHandler(name, cb)
{
  const button = document.getElementById(name) as HTMLButtonElement;
  if (button) {
    button.addEventListener('click', cb);
  }
}

function setResponse(value) {
  document.getElementById('response').textContent = JSON.stringify(value, null, 2);
}

function appendEvent(value) {
  const log = document.getElementById('events');
  const nearBottom = log.scrollTop + log.clientHeight >= log.scrollHeight - 2;
  if (log.textContent.trim() === 'Waiting for events…') {
    log.textContent = '';
  }
  log.textContent += `[${new Date().toLocaleTimeString()}] ${value}\n`;
  if (nearBottom) {
    log.scrollTop = log.scrollHeight;
  }
}

async function getUserInfo() {
  const val = await bridge.getUserInfo();
  setResponse(val);
}

async function getDeviceInfo() {
  const val = await bridge.getDeviceInfo();
  setResponse(val);
}

async function createStartup() {
  const payload = {
    containerTotalNum: 2,
    listObject: [
      {
        xPosition: 20,
        yPosition: 20,
        width: 250,
        height: 120,
        containerID: 1,
        containerName: 'list-1',
        isEventCapture: 1,
        itemContainer: {
          itemCount: 3,
          itemName: ['Home', 'Stats', 'Settings']
        }
      }
    ],
    textObject: [
      {
        xPosition: 20,
        yPosition: 150,
        width: 220,
        height: 40,
        containerID: 2,
        containerName: 'text-1',
        content: 'Hello EvenHub',
        isEventCapture: 0
      }
    ]
  };
  console.log("DONE");
  const val = await bridge.createStartUpPageContainer(payload);
  setResponse(val);
}



async function rebuildPage() {
  const payload = {
    containerTotalNum: 1,
    textObject: [
      {
        xPosition: 40,
        yPosition: 40,
        width: 280,
        height: 50,
        containerID: 3,
        containerName: 'text-2',
        content: 'Rebuilt page',
        isEventCapture: 1
      }
    ]
  };
  const val = await bridge.rebuildPageContainer(payload);
  setResponse(val);
}

async function updateText() {
  const payload = {
    containerID: 2,
    containerName: 'text-1',
    content: 'Updated text from WebView',
  };
  const val = await bridge.textContainerUpgrade(payload);
  setResponse(val);
}

async function updateImage() {
  const val = await bridge.updateImageRawData({
    containerID: 3,
    containerName: 'img-1',
    imageData: ''
  });
  setResponse(val);
}

async function shutdownPage() {
  const val = await bridge.shutDownPageContainer({ exitMode: 0 });
  setResponse(val);
}

const unsubscribe = bridge.onDeviceStatusChanged((status) => {
  //appendEvent(`deviceStatusChanged: ${JSON.stringify(status)}`);
  //if (status.connectType === DeviceConnectType.Connected) {
  //  console.log('Device connected!', status.batteryLevel);
  //}
});
//unsubscribe

const unsubscribe2 = bridge.onEvenHubEvent((event) => {
  if (event.listEvent) {
    console.log("List: ", event.listEvent);
    console.log('List selected:', event.listEvent.currentSelectItemName);
  } else if (event.textEvent) {
    console.log('Text event:', event.textEvent);
  } else if (event.sysEvent) {
    console.log('System event:', event.sysEvent.eventType);
  }
  appendEvent(`evenHubEvent: ${JSON.stringify(event)}`);
});



registerButtonHandler('bCreateStartup', createStartup)
registerButtonHandler('bGetDeviceInfo', getDeviceInfo)
registerButtonHandler('bGetUserInfo', getUserInfo)
registerButtonHandler('bRebuildPage', rebuildPage)
registerButtonHandler('bUpdateText', updateText)
registerButtonHandler('bUpdateImage', updateImage)
registerButtonHandler('bShutdownPage', shutdownPage)

document.getElementById('status').textContent = 'Bridge: ready';
