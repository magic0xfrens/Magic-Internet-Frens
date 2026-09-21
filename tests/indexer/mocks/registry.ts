export const handlers = new Map<string, (args: any) => Promise<void>>();

export const ponder = {
  on(name: string, handler: (args: any) => Promise<void>) {
    handlers.set(name, handler);
  },
};
