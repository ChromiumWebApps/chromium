// Copyright (c) 2011 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef WEBKIT_FILEAPI_FILE_WRITER_DELEGATE_H_
#define WEBKIT_FILEAPI_FILE_WRITER_DELEGATE_H_

#include "base/file_path.h"
#include "base/memory/ref_counted.h"
#include "base/memory/scoped_callback_factory.h"
#include "base/memory/scoped_ptr.h"
#include "base/message_loop_proxy.h"
#include "base/platform_file.h"
#include "base/task.h"
#include "base/time.h"
#include "net/base/completion_callback.h"
#include "net/base/file_stream.h"
#include "net/base/io_buffer.h"
#include "net/url_request/url_request.h"

namespace fileapi {

class FileSystemOperation;
class FileSystemOperationContext;

class FileWriterDelegate : public net::URLRequest::Delegate {
 public:
  FileWriterDelegate(
      FileSystemOperation* write_operation,
      int64 offset,
      scoped_refptr<base::MessageLoopProxy> proxy);
  virtual ~FileWriterDelegate();

  void Start(base::PlatformFile file,
             net::URLRequest* request,
             const FileSystemOperationContext& context);
  base::PlatformFile file() {
    return file_;
  }

  virtual void OnReceivedRedirect(
      net::URLRequest* request, const GURL& new_url, bool* defer_redirect);
  virtual void OnAuthRequired(
      net::URLRequest* request, net::AuthChallengeInfo* auth_info);
  virtual void OnCertificateRequested(
      net::URLRequest* request, net::SSLCertRequestInfo* cert_request_info);
  virtual void OnSSLCertificateError(
      net::URLRequest* request, int cert_error, net::X509Certificate* cert);
  virtual void OnResponseStarted(net::URLRequest* request);
  virtual void OnReadCompleted(net::URLRequest* request, int bytes_read);

 private:
  void OnGetFileInfoAndPrepareUsageFile(
      base::PlatformFileError error,
      const base::PlatformFileInfo& file_info,
      const FilePath& usage_file_path);
  void Read();
  void OnDataReceived(int bytes_read);
  void Write();
  void OnDataWritten(int write_response);
  void OnError(base::PlatformFileError error);
  void OnProgress(int bytes_read, bool done);

  FileSystemOperation* file_system_operation_;
  base::PlatformFile file_;
  base::PlatformFileInfo file_info_;
  int64 offset_;
  scoped_refptr<base::MessageLoopProxy> proxy_;
  base::Time last_progress_event_time_;
  int bytes_written_backlog_;
  int bytes_written_;
  int bytes_read_;
  FilePath usage_file_path_;
  int64 total_bytes_written_;
  int64 allowed_bytes_growth_;
  int64 allowed_bytes_to_write_;
  scoped_refptr<net::IOBufferWithSize> io_buffer_;
  scoped_ptr<net::FileStream> file_stream_;
  net::URLRequest* request_;
  net::CompletionCallbackImpl<FileWriterDelegate> io_callback_;
  ScopedRunnableMethodFactory<FileWriterDelegate> method_factory_;
  base::ScopedCallbackFactory<FileWriterDelegate> callback_factory_;
};

}  // namespace fileapi

#endif  // WEBKIT_FILEAPI_FILE_WRITER_DELEGATE_H_
