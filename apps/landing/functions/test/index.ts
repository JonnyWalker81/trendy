export const onRequestGet = async () => {
  console.log('[TEST] Test endpoint called!');
  return new Response('Test endpoint working!', {
    headers: { 'Content-Type': 'text/plain' },
  });
};
