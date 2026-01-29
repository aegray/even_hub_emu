import {
  waitForEvenAppBridge,
  CreateStartUpPageContainer,
  ListContainerProperty,
  TextContainerProperty,
} from '@evenrealities/even_hub_sdk';

const bridge = await waitForEvenAppBridge();

// Create containers
const listContainer: ListContainerProperty = {
  xPosition: 100,
  yPosition: 50,
  width: 200,
  height: 150,
  containerID: 1,
  containerName: 'list-1',
  itemContainer: {
    itemCount: 3,
    itemName: ['Item 1', 'Item 2', 'Item 3'],
  },
  isEventCapture: 1, // Only one container can have isEventCapture=1
};

const textContainer: TextContainerProperty = {
  xPosition: 100,
  yPosition: 220,
  width: 200,
  height: 50,
  containerID: 2,
  containerName: 'text-1',
  content: 'Hello World',
  isEventCapture: 0,
};

// Create startup page (max 4 containers)
const result = await bridge.createStartUpPageContainer({
  containerTotalNum: 2, // Maximum: 4
  listObject: [listContainer],
  textObject: [textContainer],
});

if (result === 0) {
  // Update image data if needed
  // await bridge.updateImageRawData({ ... });
  
  // Update text content if needed
  const textContainerUpdate: TextContainerProperty = {
      xPosition: 100,
      yPosition: 220,
      width: 200,
      height: 50,
      containerID: 2,
      containerName: 'text-1',
      content: 'Hello World Update',
      isEventCapture: 0,
    };
  await bridge.textContainerUpgrade(textContainerUpdate);
}

