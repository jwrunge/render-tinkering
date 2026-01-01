export class World {
    objects: unknown[] = [];
    #drawDistance: number;
    #chunkRows = 5;
    #chunkSize = 100;
    #chunks: unknown[];
    #currentChunk = 0;

    constructor(drawDistance: number) {
        this.#drawDistance = drawDistance;
    }

    set drawDistance(distance: number) {
        this.#drawDistance = distance;

        // Determine chunks based on intended draw distance
        const minChunks = 8;
        
        // Determine chunk size and rows from number of chunks

        // Set chunks
    }
}