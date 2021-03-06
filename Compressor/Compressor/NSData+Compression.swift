//The MIT License (MIT)
//
//Copyright (c) 2015 Lee Morgan
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of
//this software and associated documentation files (the "Software"), to deal in
//the Software without restriction, including without limitation the rights to
//use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//the Software, and to permit persons to whom the Software is furnished to do so,
//subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all
//copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation
import Compression

/** Available Compression Algorithms
 - Compression.LZ4   : Fast compression
 - Compression.ZLIB  : Balanced between speed and compression
 - Compression.LZMA  : High compression
 - Compression.LZFSE : Apple-specific high performance compression. Faster and better compression than ZLIB, but slower than LZ4 and does not compress as well as LZMA.
 */
enum Compression {
  
  /// Fast compression
  case LZ4
  
  /// Balanced between speed and compression
  case ZLIB
  
  /// High compression
  case LZMA
  
  /// Apple-specific high performance compression. Faster and better compression than ZLIB, but slower than LZ4 and does not compress as well as LZMA.
  case LZFSE
}

extension NSData {
  
  /// Returns a NSData object initialized by decompressing the data from the file specified by `path` using the given `compression` algorithm.
  ///
  ///     let data = NSData(contentsOfArchive: absolutePathToFile, usedCompression: Compression.LZFSE)
  ///
  /// - Parameter path: The absolute path of the file from which to read data
  /// - Parameter usedCompression: Algorithm to use during decompression. If compression is nil, attempts to determine the appropriate decompression algorithm using the path's extension
  /// - Returns: A NSData object initialized by decompressing the data from the file specified by `path` using the given `compression` algorithm. Returns `nil` if decompression fails.
  convenience init?(contentsOfArchive path: String, compression: Compression) {
    
    // read in the compressed data from disk
    guard let compressedData = NSData(contentsOfFile: path) else {
      return nil
    }
    
    // finally, attempt to uncompress the data and initalize self
    if let uncompressedData = compressedData.uncompressedDataUsingCompression(compression) {
      self.init(data: uncompressedData)
    } else {
      return nil
    }
  }
  
  
  /// Returns a NSData object created by compressing the receiver using the given compression algorithm.
  ///
  ///     let compressedData = someData.compressedDataUsingCompression(Compression.LZFSE)
  ///
  /// - Parameter compression: Algorithm to use during compression
  /// - Returns: A NSData object created by encoding the receiver's contents using the provided compression algorithm. Returns nil if compression fails or if the receiver's length is 0.
  func compressedDataUsingCompression(compression: Compression) -> NSData? {
    return self.dataUsingCompression(compression, operation: .Encode)
  }
  
  /// Returns a NSData object by uncompressing the receiver using the given compression algorithm.
  ///
  ///     let uncompressedData = someCompressedData.uncompressedDataUsingCompression(Compression.LZFSE)
  ///
  /// - Parameter compression: Algorithm to use during decompression
  /// - Returns: A NSData object created by decoding the receiver's contents using the provided compression algorithm. Returns nil if decompression fails or if the receiver's length is 0.
  func uncompressedDataUsingCompression(compression: Compression) -> NSData? {
    return self.dataUsingCompression(compression, operation: .Decode)
  }
  
  
  private enum CompressionOperation {
    case Encode
    case Decode
  }
  
  private func dataUsingCompression(compression: Compression, operation: CompressionOperation) -> NSData? {
    
    guard self.length > 0 else {
      return nil
    }
    
    let streamPtr = UnsafeMutablePointer<compression_stream>.alloc(1)
    var stream = streamPtr.memory
    var status : compression_status
    var op : compression_stream_operation
    var flags : Int32
    var algorithm : compression_algorithm
    
    switch compression {
    case .LZ4:
      algorithm = COMPRESSION_LZ4
    case .LZFSE:
      algorithm = COMPRESSION_LZFSE
    case .LZMA:
      algorithm = COMPRESSION_LZMA
    case .ZLIB:
      algorithm = COMPRESSION_ZLIB
    }
    
    switch operation {
    case .Encode:
      op = COMPRESSION_STREAM_ENCODE
      flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
    case .Decode:
      op = COMPRESSION_STREAM_DECODE
      flags = 0
    }
    
    status = compression_stream_init(&stream, op, algorithm)
    guard status != COMPRESSION_STATUS_ERROR else {
      // an error occurred
      return nil
    }
    
    // setup the stream's source
    stream.src_ptr = UnsafePointer<UInt8>(bytes)
    stream.src_size = length
    
    // setup the stream's output buffer
    // we use a temporary buffer to store the data as it's compressed
    let dstBufferSize : size_t = 4096
    let dstBufferPtr = UnsafeMutablePointer<UInt8>.alloc(dstBufferSize)
    stream.dst_ptr = dstBufferPtr
    stream.dst_size = dstBufferSize
    // and we stroe the output in a mutable data object
    let outputData = NSMutableData()
    
    
    repeat {
      status = compression_stream_process(&stream, flags)
      
      switch status.rawValue {
      case COMPRESSION_STATUS_OK.rawValue:
        // Going to call _process at least once more, so prepare for that
        if stream.dst_size == 0 {
          // Output buffer full...
          
          // Write out to mutableData
          outputData.appendBytes(dstBufferPtr, length: dstBufferSize)
          
          // Re-use dstBuffer
          stream.dst_ptr = dstBufferPtr
          stream.dst_size = dstBufferSize
        }
        
      case COMPRESSION_STATUS_END.rawValue:
        // We are done, just write out the output buffer if there's anything in it
        if stream.dst_ptr > dstBufferPtr {
          outputData.appendBytes(dstBufferPtr, length: stream.dst_ptr - dstBufferPtr)
        }
        
      case COMPRESSION_STATUS_ERROR.rawValue:
        return nil
        
      default:
        break
      }
      
    } while status == COMPRESSION_STATUS_OK
    
    compression_stream_destroy(&stream)
    
    return outputData.copy() as? NSData
  }
  
}