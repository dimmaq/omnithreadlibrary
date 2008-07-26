///<summary>Thread pool implementation. Part of the OmniThreadLibrary project.</summary>
///<author>Primoz Gabrijelcic</author>
///<license>
///This software is distributed under the BSD license.
///
///Copyright (c) 2008, Primoz Gabrijelcic
///All rights reserved.
///
///Redistribution and use in source and binary forms, with or without modification,
///are permitted provided that the following conditions are met:
///- Redistributions of source code must retain the above copyright notice, this
///  list of conditions and the following disclaimer.
///- Redistributions in binary form must reproduce the above copyright notice,
///  this list of conditions and the following disclaimer in the documentation
///  and/or other materials provided with the distribution.
///- The name of the Primoz Gabrijelcic may not be used to endorse or promote
///  products derived from this software without specific prior written permission.
///
///THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
///ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
///WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
///DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
///ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
///(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
///LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
///ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
///(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
///SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
///</license>
///<remarks><para>
///   Author            : Primoz Gabrijelcic
///   Creation date     : 2008-06-12
///   Last modification : 2008-06-30
///   Version           : 0.0
///</para><para>
///   History:
///</para></remarks>

unit OtlThreadPool;

interface

uses
  Windows,
  SysUtils,
  OtlTask;

const
  CDefaultIdleWorkerThreadTimeout_sec = 10;
  CDefaultWaitOnTerminate_sec         = 30;

  // error codes
  ERR_EXECUTION_QUEUE_TOO_LONG = -1;
  ERR_WORK_ITEM_TOO_OLD        = -2;

type
  ///<summary>Work thread lifetime reporting handler.</summary>
  TOTPWorkerThreadEvent = procedure(Sender: TObject; threadID: DWORD) of object;

  IOmniThreadPool = interface ['{1FA74554-1866-46DD-AC50-F0403E378682}']
    function  GetIdleWorkerThreadTimeout_sec: integer;
    function  GetMaxExecuting: integer;
    function  GetMaxQueued: integer; 
    function  GetMaxQueuedTime_sec: integer; 
    function  GetMinWorkers: integer; 
    function  GetName: string;
    function  GetOnWorkerThreadCreated_Asy: TOTPWorkerThreadEvent; 
    function  GetOnWorkerThreadDestroying_Asy: TOTPWorkerThreadEvent;
    function  GetWaitOnTerminate_sec: integer;
    procedure SetIdleWorkerThreadTimeout_sec(value: integer);
    procedure SetMaxExecuting(value: integer);
    procedure SetMaxQueued(value: integer);
    procedure SetMaxQueuedTime_sec(value: integer);
    procedure SetMinWorkers(value: integer);
    procedure SetName(const value: string);
    procedure SetWaitOnTerminate_sec(value: integer);
    procedure SetOnWorkerThreadCreated_Asy(const value: TOTPWorkerThreadEvent);
    procedure SetOnWorkerThreadDestroying_Asy(const value: TOTPWorkerThreadEvent);
  //
    procedure Schedule(task: IOmniTask);
    property IdleWorkerThreadTimeout_sec: integer read GetIdleWorkerThreadTimeout_sec
      write SetIdleWorkerThreadTimeout_sec;
    property MaxExecuting: integer read GetMaxExecuting write SetMaxExecuting;
    property MaxQueued: integer read GetMaxQueued write SetMaxQueued;
    property MaxQueuedTime_sec: integer read GetMaxQueuedTime_sec write SetMaxQueuedTime_sec;
    property MinWorkers: integer read GetMinWorkers write SetMinWorkers;
    property Name: string read GetName write SetName;
    property WaitOnTerminate_sec: integer read GetWaitOnTerminate_sec write
      SetWaitOnTerminate_sec;
    property OnWorkerThreadCreated_Asy: TOTPWorkerThreadEvent read
      GetOnWorkerThreadCreated_Asy write SetOnWorkerThreadCreated_Asy;
    property OnWorkerThreadDestroying_Asy: TOTPWorkerThreadEvent read
      GetOnWorkerThreadDestroying_Asy write SetOnWorkerThreadDestroying_Asy;
  //thrown in from my private thread pool unit; to be cleaned up
  {
    procedure CancelAll;
    procedure Cancel(workItemID: int64); <-- task?
    //function  GetActiveWorkItemDescriptions: string; <-- debugging interface, does not belong here
    function  IsIdle: boolean;
    property CountExecuting: integer read GetExecutingCount;
    property CountQueued: integer read GetQueuedCount;
    property OnError: TGpTPError read tpOnError write tpOnError;
    property OnWorkItemDone: TGpTPWorkItemDone read tpOnWorkItemDone write tpOnWorkItemDone;
  }
  end; { IOmniThreadPool }

  function CreateThreadPool(const threadPoolName: string): IOmniThreadPool;

  function GlobalOmniThreadPool: IOmniThreadPool;

implementation

uses
  Messages,
  Classes,
  Contnrs,
  DSiWin32,
  SpinLock,
  HVStringBuilder,
  OtlCommon;

const
  WM_REQUEST_COMPLETED = WM_USER;

type
  ///<enum name='tsUnknownError'>An unknown error has occured.</enum>
  ///<enum name='tsCompleted'>Work item has completed execution.</enum>
  ///<enum name='tsException'>Work item's Execute method has raised an exception.</enum>
  ///<enum name='tsCanceled'>Application called CancelAll.</enum>
  ///<enum name='tsServerBusy'>Server is too busy.</enum>
  TOTPTaskStatus = (tsUnknownError, tsCompleted, tsException, tsCanceled, tsServerBusy);

  TOTPWorkItem = class
  strict private
    owiScheduledAt       : TDateTime;
    owiLastError         : string;
    owiScheduled_ms      : int64;
    owiStartedAt         : TDateTime;
    owiStatus            : TOTPTaskStatus;
    owiTask              : IOmniTask;
    owiTerminateExecution: boolean;
  strict protected
    function  GetUniqueID: int64;
  public
    constructor Create(task: IOmniTask);
    function  Description: string;
    procedure SetLastError(status: TOTPTaskStatus; const errorMsg: string);
    property LastError: string read owiLastError;
    property ScheduledAt: TDateTime read owiScheduledAt;
    property Scheduled_ms: int64 read owiScheduled_ms;
    property StartedAt: TDateTime read owiStartedAt write owiStartedAt;
    property Status: TOTPTaskStatus read owiStatus;
    property TerminateExecution: boolean read owiTerminateExecution write owiTerminateExecution;
    property UniqueID: int64 read GetUniqueID;
    property Task: IOmniTask read owiTask;
  end; { TOTPWorkItem }

  TOmniThreadPool = class;

  TOTPWorkerThread = class(TThread)
  private
    owtNewWorkEvent     : TDSiEventHandle;
    owtOwner            : TOmniThreadPool;
    owtRemoveFromPool   : boolean;
    owtStartIdle_ms     : int64;
    owtStartStopping_ms : int64;
    owtTerminateEvent   : TDSiEventHandle;
    owtWorkItemLock     : TTicketSpinLock;
    owtWorkItem_ref     : TOTPWorkItem;
  protected
    procedure Log(const msg: string; params: array of const);
  public
    constructor Create(owner: TOmniThreadPool);
    destructor  Destroy; override;
    procedure Asy_Stop;
    function  Asy_TerminateWorkItem: boolean;
    function  Description: string;
    procedure Execute; override;
    function  GetWorkItemInfo(var scheduledAt, startedAt: TDateTime;
      var description: string): boolean;
    function  IsExecuting(taskID: int64): boolean;
    function  WorkItemDescription: string;
    property NewWorkEvent: TDSiEventHandle read owtNewWorkEvent;
    property Owner: TOmniThreadPool read owtOwner;
    property RemoveFromPool: boolean read owtRemoveFromPool;
    property StartIdle_ms: int64 read owtStartIdle_ms write owtStartIdle_ms;
    property StartStopping_ms: int64 read owtStartStopping_ms write owtStartStopping_ms;
    property TerminateEvent: TDSiEventHandle read owtTerminateEvent;
    property WorkItem_ref: TOTPWorkItem read owtWorkItem_ref write owtWorkItem_ref; //address of the work item this thread is working on
  end; { TOTPWorkerThread }

  TOmniThreadPool = class(TInterfacedObject, IOmniThreadPool)
  strict private
    otpDestroying                 : boolean;
    otpHWnd                       : HWND;
    otpIdleWorkers                : TObjectList {of TOTPWorkerThread};
    otpIdleWorkerThreadTimeout_sec: integer;
    otpMaintainanceTimer          : TDSiTimer;
    otpMaxExecuting               : integer;
    otpMaxQueued                  : integer;
    otpMaxQueuedTime_sec          : integer;
    otpMinWorkers                 : integer;
    otpName                       : string;
    otpOnWorkerThreadCreated      : TOTPWorkerThreadEvent;
    otpOnWorkerThreadDestroying   : TOTPWorkerThreadEvent;
    otpRunningWorkers             : TObjectList {of TOTPWorkerThread};
    otpStoppingWorkers            : TObjectList {of TOTPWorkerThread};
    otpWaitOnTerminate_sec        : integer;
    otpWorkItemQueue              : TObjectList {of TOTPWorkItem};
  strict protected
    procedure InternalStop;
    procedure Log(const msg: string; params: array of const);
    procedure MaintainanceTimer(Sender: TObject);
    function  NumRunningStoppedThreads: integer;
    procedure PruneWorkingQueue;
    procedure ReportError(errorCode: integer; const errorMessage: string);
    procedure ScheduleNext(workItem: TOTPWorkItem);
    procedure StopThread(worker: TOTPWorkerThread);
    procedure WndProc(var msg: TMessage);
  protected
    procedure Asy_ForwardThreadCreated(threadID: DWORD);
    procedure Asy_ForwardThreadDestroying(threadID: DWORD);
    procedure Asy_RequestCompleted(workItem: TOTPWorkItem; worker: TOTPWorkerThread);
    function  GetIdleWorkerThreadTimeout_sec: integer;
    function  GetMaxExecuting: integer;
    function  GetMaxQueued: integer;
    function  GetMaxQueuedTime_sec: integer;
    function  GetMinWorkers: integer;
    function  GetName: string;
    function  GetOnWorkerThreadCreated_Asy: TOTPWorkerThreadEvent;
    function  GetOnWorkerThreadDestroying_Asy: TOTPWorkerThreadEvent;
    function  GetWaitOnTerminate_sec: integer;
    procedure SetIdleWorkerThreadTimeout_sec(value: integer);
    procedure SetMaxExecuting(value: integer);
    procedure SetMaxQueued(value: integer);
    procedure SetMaxQueuedTime_sec(value: integer);
    procedure SetMinWorkers(value: integer);
    procedure SetName(const value: string);
    procedure SetOnWorkerThreadCreated_Asy(const value: TOTPWorkerThreadEvent);
    procedure SetOnWorkerThreadDestroying_Asy(const value: TOTPWorkerThreadEvent);
    procedure SetWaitOnTerminate_sec(value: integer);
  public
    constructor Create(const name: string);
    destructor  Destroy; override;
    function  GetActiveWorkItemDescriptions: string;
    procedure Schedule(task: IOmniTask);
    property IdleWorkerThreadTimeout_sec: integer read GetIdleWorkerThreadTimeout_sec
      write SetIdleWorkerThreadTimeout_sec;
    property MaxExecuting: integer read GetMaxExecuting write SetMaxExecuting;
    property MaxQueued: integer read GetMaxQueued write SetMaxQueued;
    property MaxQueuedTime_sec: integer read GetMaxQueuedTime_sec write SetMaxQueuedTime_sec;
    property MinWorkers: integer read GetMinWorkers write SetMinWorkers;
    property Name: string read GetName write SetName;
    property WaitOnTerminate_sec: integer read GetWaitOnTerminate_sec write
      SetWaitOnTerminate_sec;
    property OnWorkerThreadCreated_Asy: TOTPWorkerThreadEvent
      read GetOnWorkerThreadCreated_Asy write SetOnWorkerThreadCreated_Asy;
    property OnWorkerThreadDestroying_Asy: TOTPWorkerThreadEvent
      read GetOnWorkerThreadDestroying_Asy write SetOnWorkerThreadDestroying_Asy;
  end; { TOmniThreadPool }

const
  CGlobalOmniThreadPoolName = 'GlobalOmniThreadPool';

var
  GOmniThreadPool: IOmniThreadPool = nil;

{ exports }

function GlobalOmniThreadPool: IOmniThreadPool;
begin
  if not assigned(GOmniThreadPool) then
    GOmniThreadPool := CreateThreadPool(CGlobalOmniThreadPoolName);
  Result := GOmniThreadPool;
end; { GlobalOmniThreadPool }

function CreateThreadPool(const threadPoolName: string): IOmniThreadPool;
begin
  Result := TOmniThreadPool.Create(threadPoolName);
end; { CreateThreadPool }

{ TOTPWorkItem }

constructor TOTPWorkItem.Create(task: IOmniTask);
begin
  inherited Create;
  owiTask := task;
  owiScheduledAt := Now;
  owiScheduled_ms := DSiTimeGetTime64;
  SetLastError(tsUnknownError, 'Scheduled');
end; { TOTPWorkItem.Create }

function TOTPWorkItem.Description: string;
begin
  Result := Format('%s:%d', [Task.Name, UniqueID]);
end; { TOTPWorkItem.Description }

function TOTPWorkItem.GetUniqueID: int64;
begin
  Result := Task.UniqueID;
end; { TOTPWorkItem.GetUniqueID }

procedure TOTPWorkItem.SetLastError(status: TOTPTaskStatus; const errorMsg: string);
begin
  owiStatus := status;
  owiLastError := errorMsg;
  UniqueString(owiLastError);
end; { TOTPWorkItem.SetLastError }

{ TOTPWorkerThread }

constructor TOTPWorkerThread.Create(owner: TOmniThreadPool);
begin
  inherited Create(true);
  owtOwner := owner;
  {$IFDEF LogThreadPool}Log('Creating thread %s', [Description]);{$ENDIF LogThreadPool}
  owtNewWorkEvent := CreateEvent(nil, false, false, nil);
  owtTerminateEvent := CreateEvent(nil, false, false, nil);
  owtWorkItemLock := TTicketSpinLock.Create;
  Resume;
end; { TOTPWorkerThread.Create }

destructor TOTPWorkerThread.Destroy;
begin
  {$IFDEF LogThreadPool}Log('Destroying thread %s', [Description]);{$ENDIF LogThreadPool}
  FreeAndNil(owtWorkItemLock);
  DSiCloseHandleAndNull(owtTerminateEvent);
  DSiCloseHandleAndNull(owtNewWorkEvent);
  inherited Destroy;
end; { TOTPWorkerThread.Destroy }

///<summary>Gently stop the worker thread. Called asynchronously from the thread pool.</summary>
procedure TOTPWorkerThread.Asy_Stop;
begin
  {$IFDEF LogThreadPool}Log('Asy_Stop thread %s', [Description]);{$ENDIF LogThreadPool}
  StartStopping_ms := DSiTimeGetTime64;
  owtWorkItemLock.Acquire;
  try
    if assigned(WorkItem_ref) then
      WorkItem_ref.TerminateExecution := true;
  finally owtWorkItemLock.Release end;
  SetEvent(TerminateEvent);
end; { TOTPWorkerThread.Asy_Stop }

///<summary>Take the work item ownership from the thread. Called asynchronously from the thread pool.</summary>
function TOTPWorkerThread.Asy_TerminateWorkItem: boolean;
var
  workItem: TOTPWorkItem;
begin
  {$IFDEF LogThreadPool}Log('Asy_TerminateWorkItem thread %s', [Description]);{$ENDIF LogThreadPool}
  Result := false;
  owtWorkItemLock.Acquire;
  try
    if assigned(WorkItem_ref) then begin
      {$IFDEF LogThreadPool}Log('Thread %s has work item', [Description]);{$ENDIF LogThreadPool}
      workItem := WorkItem_ref;
      WorkItem_ref := nil;
      workItem.SetLastError(tsCanceled, 'Cancelled');
      Owner.Asy_RequestCompleted(workItem, Self);
      Result := true;
    end;
  finally owtWorkItemLock.Release end;
end; { TOTPWorkerThread.Asy_TerminateWorkItem }

function TOTPWorkerThread.Description: string;
begin
  if not assigned(Self) then
    Result := '<none>'
  else
    Result := Format('%p:%d', [pointer(Self), GetCurrentThreadID]);
end; { TOTPWorkerThread.Description }

procedure TOTPWorkerThread.Execute;
var
  creationTime   : TDateTime;
  startKernelTime: int64;
  startUserTime  : int64;
  stopKernelTime : int64;
  stopUserTime   : int64;
  workItem       : TOTPWorkItem;
begin
  {$IFDEF LogThreadPool}Log('>>>Execute thread %s', [Description]);{$ENDIF LogThreadPool}
    owtOwner.Asy_ForwardThreadCreated(ThreadID);
    try
      while DSiWaitForTwoObjects(owtNewWorkEvent, TerminateEvent, false, INFINITE) = WAIT_OBJECT_0 do begin
        try
          {$IFDEF LogThreadPool}Log('Thread %s starting execution of %s', [Description, WorkItem_ref.Description]);{$ENDIF LogThreadPool}
          DSiGetThreadTimes(creationTime, startUserTime, startKernelTime);
          {$IFNDEF OTL_DontSetThreadName}
          SetThreadName(WorkItem_ref.Task.Name);
          {$ENDIF OTL_DontSetThreadName}
          (WorkItem_ref.Task as IOmniTaskExecutor).Execute;
          DSiGetThreadTimes(creationTime, stopUserTime, stopKernelTime);
          WorkItem_ref.SetLastError(tsCompleted, '');
          {$IFDEF LogThreadPool}Log('Thread %s completed execution of %s; user time = %d ms, kernel time = %d ms', [Description, WorkItem_ref.Description, Round((stopUserTime - startUserTime)/10000), Round((stopKernelTime - startKernelTime)/10000)]);{$ENDIF LogThreadPool}
        except
          on E: Exception do begin
// TODO 1 -oPrimoz Gabrijelcic : implement: TOTPWorkerThread.Execute
//            LogSilentException(ClassName+'.Execute');
            {$IFDEF LogThreadPool}Log('Thread %s caught exception %s during exection of %s', [Description, E.Message, WorkItem_ref.Description]);{$ENDIF LogThreadPool}
            WorkItem_ref.SetLastError(tsException, E.Message);
            owtRemoveFromPool := true;
          end;
        end;
        owtWorkItemLock.Acquire;
        try
          workItem := WorkItem_ref;
          WorkItem_ref := nil;
          if assigned(workItem) then begin
            {$IFDEF LogThreadPool}Log('Thread %s sending notification of completed work item %s', [Description, workItem.Description]);{$ENDIF LogThreadPool}
            Owner.Asy_RequestCompleted(workItem, Self);
          end;
        finally owtWorkItemLock.Release; end;
      end; //while
    finally owtOwner.Asy_ForwardThreadDestroying(ThreadID); end;
  {$IFDEF LogThreadPool}Log('<<<Execute thread %s', [Description]);{$ENDIF LogThreadPool}
end; { TOTPWorkerThread.Execute }

function TOTPWorkerThread.GetWorkItemInfo(var scheduledAt, startedAt: TDateTime; var
  description: string): boolean;
begin
  owtWorkItemLock.Acquire;
  try
    if not assigned(WorkItem_ref) then
      Result := false
    else begin
      scheduledAt := WorkItem_ref.ScheduledAt;
      startedAt := WorkItem_ref.StartedAt;
      description := WorkItem_ref.Description; UniqueString(description);
      Result := true;
    end;
  finally owtWorkItemLock.Release; end;
end; { TOTPWorkerThread.GetWorkItemInfo }

function TOTPWorkerThread.IsExecuting(taskID: int64): boolean;
begin
  owtWorkItemLock.Acquire;
  try
    Result := assigned(WorkItem_ref) and (WorkItem_ref.UniqueID = taskID);
  finally owtWorkItemLock.Release; end;
end; { TOTPWorkerThread.IsExecuting }

procedure TOTPWorkerThread.Log(const msg: string; params: array of const);
begin
  {$IFDEF LogThreadPool}
  Owner.Log(msg, params);
  {$ENDIF LogThreadPool}
end; { TOTPWorkerThread.Log }

function TOTPWorkerThread.WorkItemDescription: string;
begin
  owtWorkItemLock.Acquire;
  try
    if assigned(WorkItem_ref) then begin
      Result := WorkItem_ref.Description;
    end
    else
      Result := '';
  finally owtWorkItemLock.Release; end;
end; { TOTPWorkerThread.WorkItemDescription }

{ TOmniThreadPool }

constructor TOmniThreadPool.Create(const name: string);
begin
  inherited Create;
  otpName := name;
  {$IFDEF LogThreadPool}Log('Creating thread pool %p', [pointer(self)]);{$ENDIF LogThreadPool}
  otpIdleWorkers := TObjectList.Create(false);
  otpRunningWorkers := TObjectList.Create(false);
  otpStoppingWorkers := TObjectList.Create(false);
  otpWorkItemQueue := TObjectList.Create(false);
  otpIdleWorkerThreadTimeout_sec := CDefaultIdleWorkerThreadTimeout_sec;
  otpWaitOnTerminate_sec := CDefaultWaitOnTerminate_sec;
  otpMaxExecuting := Length(DSiGetThreadAffinity);
  otpHWnd := DSiAllocateHWnd(WndProc);
  otpMaintainanceTimer := TDSiTimer.Create(true, 1000, MaintainanceTimer);
end; { TOmniThreadPool.Create }

destructor TOmniThreadPool.Destroy;
begin
  {$IFDEF LogThreadPool}Log('Destroying thread pool %p', [pointer(self)]);{$ENDIF LogThreadPool}
  otpDestroying := true;
  FreeAndNil(otpMaintainanceTimer);
  InternalStop;
  DSiDeallocateHWnd(otpHWnd);
  FreeAndNil(otpStoppingWorkers);
  FreeAndNil(otpRunningWorkers);
  FreeAndNil(otpIdleWorkers);
  FreeAndNil(otpWorkItemQueue);
  inherited;
end; { TOmniThreadPool.Destroy }

procedure TOmniThreadPool.Asy_ForwardThreadCreated(threadID: DWORD);
begin
  if assigned(OnWorkerThreadCreated_Asy) then
    OnWorkerThreadCreated_Asy(Self, threadID);
end; { TOmniThreadPool.Asy_ForwardThreadCreated }

procedure TOmniThreadPool.Asy_ForwardThreadDestroying(threadID: DWORD);
begin
  if assigned(OnWorkerThreadDestroying_Asy) then
    OnWorkerThreadDestroying_Asy(Self, threadID);
end; { TOmniThreadPool.Asy_ForwardThreadDestroying }

procedure TOmniThreadPool.Asy_RequestCompleted(workItem: TOTPWorkItem; worker:
  TOTPWorkerThread);
begin
  {$IFDEF LogThreadPool}Log('Asy: Thread %s completed request %s with status %s:%s',
    [worker.Description, workItem.Description, GetEnumName(TypeInfo(TGpTPStatus), Ord(workItem.Status)), workItem.LastError]);{$ENDIF LogThreadPool}
  if otpDestroying then
    FreeAndNil(workItem)
  else
    PostMessage(otpHWnd, WM_REQUEST_COMPLETED, WParam(workItem), LParam(worker));
end; { TOmniThreadPool.Asy_RequestCompleted }

function TOmniThreadPool.GetActiveWorkItemDescriptions: string;
var
  description   : string;
  iWorker       : integer;
  sbDescriptions: StringBuilder;
  scheduledAt   : TDateTime;
  startedAt     : TDateTime;
  worker        : TOTPWorkerThread;
begin
  sbDescriptions := StringBuilder.Create;
  try
    for iWorker := 0 to otpRunningWorkers.Count - 1 do begin
      worker := TOTPWorkerThread(otpRunningWorkers[iWorker]);
      if worker.GetWorkItemInfo(scheduledAt, startedAt, description) then
        sbDescriptions.
          Append('[').Append(iWorker+1).Append('] ').
          Append(FormatDateTime('hh:nn:ss', scheduledAt)).Append(' / ').
          Append(FormatDateTime('hh:nn:ss', startedAt)).Append(' ').
          Append(description);
    end;
  Result := sbDescriptions.ToString;
  finally FreeAndNil(sbDescriptions); end;
end; { TGpThreadPool.GetActiveWorkItemDescriptions }

function TOmniThreadPool.GetIdleWorkerThreadTimeout_sec: integer;
begin
  Result := otpIdleWorkerThreadTimeout_sec;
end; { TOmniThreadPool.GetIdleWorkerThreadTimeout_sec }

function TOmniThreadPool.GetMaxExecuting: integer;
begin
  Result := otpMaxExecuting;
end; { TOmniThreadPool.GetMaxExecuting }

function TOmniThreadPool.GetMaxQueued: integer;
begin
  Result := otpMaxQueued;
end; { TOmniThreadPool.GetMaxQueued }

function TOmniThreadPool.GetMaxQueuedTime_sec: integer;
begin
  Result := otpMaxQueuedTime_sec;
end; { TOmniThreadPool.GetMaxQueuedTime_sec }

function TOmniThreadPool.GetMinWorkers: integer;
begin
  Result := otpMinWorkers;
end; { TOmniThreadPool.GetMinWorkers }

function TOmniThreadPool.GetName: string;
begin
  Result := otpName;
end; { TOmniThreadPool.GetName }

function TOmniThreadPool.GetOnWorkerThreadCreated_Asy: TOTPWorkerThreadEvent;
begin
  Result := otpOnWorkerThreadCreated;
end;

function TOmniThreadPool.GetOnWorkerThreadDestroying_Asy: TOTPWorkerThreadEvent;
begin
  Result := otpOnWorkerThreadDestroying;
end; { TOmniThreadPool.GetOnWorkerThreadDestroying_Asy }

function TOmniThreadPool.GetWaitOnTerminate_sec: integer;
begin
  Result := otpWaitOnTerminate_sec;
end; { TOmniThreadPool.GetWaitOnTerminate_sec }

procedure TOmniThreadPool.InternalStop;
var
  endWait_ms: int64;
  iWorker   : integer;
  iWorkItem : integer;
  worker    : TOTPWorkerThread;
  workItem  : TOTPWorkItem;
begin
  {$IFDEF LogThreadPool}Log('Stopping all threads', []);{$ENDIF LogThreadPool}
  for iWorker := 0 to otpIdleWorkers.Count - 1 do
    StopThread(TOTPWorkerThread(otpIdleWorkers[iWorker]));
  otpIdleWorkers.Clear;
  for iWorker := 0 to otpRunningWorkers.Count - 1 do
    StopThread(TOTPWorkerThread(otpRunningWorkers[iWorker]));
  otpRunningWorkers.Clear;
  for iWorkItem := 0 to otpWorkItemQueue.Count - 1 do begin
    workItem := TOTPWorkItem(otpWorkItemQueue[iWorkItem]);
    workItem.SetLastError(tsCanceled, 'Cancelled');
    Asy_RequestCompleted(workItem, nil);
  end; //for iWorkItem
  endWait_ms := DSiTimeGetTime64 + int64(WaitOnTerminate_sec)*1000;
  while (endWait_ms > DSiTimeGetTime64) and (NumRunningStoppedThreads > 0) do
    Sleep(100);
  for iWorker := 0 to otpStoppingWorkers.Count - 1 do begin
    worker := TOTPWorkerThread(otpStoppingWorkers[iWorker]);
    worker.Asy_TerminateWorkItem;
    FreeAndNil(worker);
  end;
  otpStoppingWorkers.Clear;
end; { TGpThreadPool.InternalStop }

procedure TOmniThreadPool.Log(const msg: string; params: array of const);
begin
  {$IFDEF LogThreadPool}
// TODO 1 -oPrimoz Gabrijelcic : implement: TOmniThreadPool.Log  
//  GpLog.Log(Format('thread pool|%p:%s|%s', [pointer(Self), Name, msg]), params);
  {$ENDIF LogThreadPool}
end; { TGpThreadPool.Log }

procedure TOmniThreadPool.MaintainanceTimer(Sender: TObject);
var
  iWorker: integer;
  worker : TOTPWorkerThread;
begin
  if IdleWorkerThreadTimeout_sec > 0 then begin
    iWorker := 0;
    while (otpIdleWorkers.Count > otpMinWorkers) and (iWorker < otpIdleWorkers.Count) do begin
      worker := TOTPWorkerThread(otpIdleWorkers[iWorker]);
      if (worker.StartStopping_ms = 0) and
         ((worker.StartIdle_ms + int64(IdleWorkerThreadTimeout_sec)*1000) < DSiTimeGetTime64) then
      begin
        {$IFDEF LogThreadPool}Log('Destroying idle thread %s because it was idle for more than %d seconds', [worker.Description, IdleWorkerThreadTimeout_sec]);{$ENDIF LogThreadPool}
        otpIdleWorkers.Delete(iWorker);
        StopThread(worker);
      end
      else
        Inc(iWorker);
    end; //while
  end;
  iWorker := 0;
  while iWorker < otpStoppingWorkers.Count do begin
    worker := TOTPWorkerThread(otpStoppingWorkers[iWorker]);
    if (not assigned(worker.WorkItem_ref)) or
       ((worker.StartStopping_ms + int64(WaitOnTerminate_sec)*1000) < DSiTimeGetTime64) then
    begin
      otpStoppingWorkers.Delete(iWorker);
      {$IFDEF LogThreadPool}Log('Removing stopped thread %s', [worker.Description]);{$ENDIF LogThreadPool}
      FreeAndNil(worker);
    end
    else
      Inc(iWorker);
  end;
end; { TOmniThreadPool.MaintainanceTimer }

///<summary>Counts number of threads in the 'stopping' queue that are still doing work.</summary>
///<since>2007-07-10</since>
function TOmniThreadPool.NumRunningStoppedThreads: integer;
var
  iThread: integer;
  worker : TOTPWorkerThread;
begin
  Result := 0;
  for iThread := 0 to otpStoppingWorkers.Count - 1 do begin
    worker := TOTPWorkerThread(otpStoppingWorkers[iThread]);
    if assigned(worker.WorkItem_ref) then
      Inc(Result);
  end; //for iThread
end; { TOmniThreadPool.NumRunningStoppedThreads }

procedure TOmniThreadPool.PruneWorkingQueue;
var
  iWorkItem     : integer;
  maxWaitTime_ms: int64;
  workItem      : TOTPWorkItem;
begin
  if otpMaxQueued > 0 then begin
    while otpWorkItemQueue.Count > otpMaxQueued do begin
      workItem := TOTPWorkItem(otpWorkItemQueue[otpWorkItemQueue.Count - 1]);
      {$IFDEF LogThreadPool}Log('Removing request %s from work item queue because queue length > %d', [workItem.Description, tpMaxQueueLength]);{$ENDIF LogThreadPool}
      otpWorkItemQueue.Delete(otpWorkItemQueue.Count - 1);
      workItem.SetLastError(tsServerBusy,
        Format('Execution queue is too long (%d work items)', [otpWorkItemQueue.Count]));
      ReportError(ERR_EXECUTION_QUEUE_TOO_LONG, workItem.LastError);
      Asy_RequestCompleted(workItem, nil);
    end; //while
  end;
  if otpMaxQueuedTime_sec > 0 then begin
    iWorkItem := 0;
    while iWorkItem < otpWorkItemQueue.Count do begin
      workItem := TOTPWorkItem(otpWorkItemQueue[iWorkItem]);
      maxWaitTime_ms := workItem.Scheduled_ms + int64(otpMaxQueuedTime_sec)*1000;
      if maxWaitTime_ms > DSiTimeGetTime64 then
        Inc(iWorkItem)
      else begin
        {$IFDEF LogThreadPool}Log('Removing request %s from work item queue because it is older than %d seconds', [workItem.Description, tpMaxQueuedTime_sec]);{$ENDIF LogThreadPool}
        otpWorkItemQueue.Delete(iWorkItem);
        workItem.SetLastError(tsServerBusy, Format(
          'Maximum queued time exceeded.' +
          ' Pool = %0:s, Now = %1:s, Max executing = %2:d,' +
          ' Removed entry queue time = %3:s, Removed entry description = %4:s.' +
          ' Active entries: %5:s',
          [{0}Name, {1}FormatDateTime('hh:nn:ss', Now), {2}MaxExecuting,
           {3}FormatDateTime('hh:nn:ss', workItem.ScheduledAt),
           {4}workItem.Description, {5}GetActiveWorkItemDescriptions]));
        ReportError(ERR_WORK_ITEM_TOO_OLD, workItem.LastError);
        Asy_RequestCompleted(workItem, nil);
      end;
    end; //while
  end;
end; { TOmniThreadPool.PruneWorkingQueue } 

procedure TOmniThreadPool.ReportError(errorCode: integer; const errorMessage: string);
begin
  // TODO 1 -oPrimoz Gabrijelcic : implement: TOmniThreadPool.ReportError
//  if assigned(OnError) then
//    OnError(Self, errorCode, errorMessage);
end; { TOmniThreadPool.ReportError }

procedure TOmniThreadPool.Schedule(task: IOmniTask);
begin
  ScheduleNext(TOTPWorkItem.Create(task));
  PruneWorkingQueue;
end; { TOmniThreadPool.Schedule }

procedure TOmniThreadPool.ScheduleNext(workItem: TOTPWorkItem);
var
  worker: TOTPWorkerThread;
begin
  worker := nil;
  if otpIdleWorkers.Count > 0 then begin
    worker := TOTPWorkerThread(otpIdleWorkers[otpIdleWorkers.Count - 1]);
    otpIdleWorkers.Delete(otpIdleWorkers.Count - 1);
    otpRunningWorkers.Add(worker);
    {$IFDEF LogThreadPool}Log('Allocated thread from idle pool, num idle = %d, num running = %d[%d]', [otpIdleWorkers.Count, otpRunningWorkers.Count, MaxExecuting]);{$ENDIF LogThreadPool}
  end
  else if (otpMaxExecuting <= 0) or (otpRunningWorkers.Count < otpMaxExecuting) then begin
    worker := TOTPWorkerThread.Create(Self);
    otpRunningWorkers.Add(worker);
    {$IFDEF LogThreadPool}Log('Created new thread %s, num idle = %d, num running = %d[%d]', [worker.Description, otpIdleWorkers.Count, otpRunningWorkers.Count, MaxExecuting]);{$ENDIF LogThreadPool}
  end;
  if assigned(worker) then begin
    {$IFDEF LogThreadPool}Log('Started %s', [workItem.Description]);{$ENDIF LogThreadPool}
    workItem.StartedAt := Now;
    worker.WorkItem_ref := workItem;
    SetEvent(worker.NewWorkEvent);
  end
  else begin
    {$IFDEF LogThreadPool}Log('Queued %s ', [workItem.Description]);{$ENDIF LogThreadPool}
    otpWorkItemQueue.Add(workItem);
  end;
end; { TOmniThreadPool.ScheduleNext }

procedure TOmniThreadPool.SetIdleWorkerThreadTimeout_sec(value: integer);
begin
  otpIdleWorkerThreadTimeout_sec := value;
end; { TOmniThreadPool.SetIdleWorkerThreadTimeout_sec }

procedure TOmniThreadPool.SetMaxExecuting(value: integer);
begin
  otpMaxExecuting := value;
end; { TOmniThreadPool.SetMaxExecuting }

procedure TOmniThreadPool.SetMaxQueued(value: integer);
begin
  otpMaxQueued := value;
  PruneWorkingQueue;
end; { TOmniThreadPool.SetMaxQueued }

procedure TOmniThreadPool.SetMaxQueuedTime_sec(value: integer);
begin
  otpMaxQueuedTime_sec := value;
  PruneWorkingQueue;
end; { TOmniThreadPool.SetMaxQueuedTime_sec }

procedure TOmniThreadPool.SetMinWorkers(value: integer);
begin
  otpMinWorkers := value;
end; { TOmniThreadPool.SetMinWorkers }

procedure TOmniThreadPool.SetName(const value: string);
begin
  otpName := value;
end; { TOmniThreadPool.SetName }

procedure TOmniThreadPool.SetOnWorkerThreadCreated_Asy(const value:
  TOTPWorkerThreadEvent);
begin
  otpOnWorkerThreadCreated := value;
end; { TOmniThreadPool.SetOnWorkerThreadCreated_Asy }

procedure TOmniThreadPool.SetOnWorkerThreadDestroying_Asy(const value:
  TOTPWorkerThreadEvent);
begin
  otpOnWorkerThreadDestroying := value;
end; { TOmniThreadPool.SetOnWorkerThreadDestroying_Asy }

procedure TOmniThreadPool.SetWaitOnTerminate_sec(value: integer);
begin
  otpWaitOnTerminate_sec := value;
end; { TOmniThreadPool.SetWaitOnTerminate_sec }

///<summary>Move the thread to the 'stopping' list and tell it to CancelAll.<para>
///   Thread is guaranted not to be in 'idle' or 'working' list when StopThread is called.</para></summary>
///<since>2007-07-10</since>
procedure TOmniThreadPool.StopThread(worker: TOTPWorkerThread);
begin
  {$IFDEF LogThreadPool}Log('Stopping worker thread %s', [worker.Description]);{$ENDIF LogThreadPool}
  worker.Asy_Stop;
  otpStoppingWorkers.Add(worker);
  {$IFDEF LogThreadPool}Log('num stopped = %d', [tpStoppingWorkers.Count]);{$ENDIF LogThreadPool}
end; { TOmniThreadPool.StopThread }

procedure TOmniThreadPool.WndProc(var msg: TMessage);
var
  worker  : TOTPWorkerThread;
  workItem: TOTPWorkItem;
begin
  if msg.Msg = WM_REQUEST_COMPLETED then begin
    workItem := TOTPWorkItem(msg.WParam);
    worker := TOTPWorkerThread(msg.LParam);
    {$IFDEF LogThreadPool}Log('Thread %s completed request %s with status %s:%s', [worker.Description, workItem.Description, GetEnumName(TypeInfo(TGpTPStatus), Ord(workItem.Status)), workItem.LastError]);{$ENDIF LogThreadPool}
//' map errors into task error codes?    
// TODO 1 -oPrimoz Gabrijelcic : implement: TOmniThreadPool.WndProc    
//    if assigned(tpOnWorkItemDone) and (not tpDestroying) then
//      tpOnWorkItemDone(Self, workItem);
    {$IFDEF LogThreadPool}Log('Destroying %s', [workItem.Description]);{$ENDIF LogThreadPool}
    FreeAndNil(workItem);
    if assigned(worker) then begin // move it back to the idle queue
      otpRunningWorkers.Extract(worker);
      if (not worker.RemoveFromPool) and (otpRunningWorkers.Count < otpMaxExecuting) then begin
        worker.StartIdle_ms := DSiTimeGetTime64;
        otpIdleWorkers.Add(worker);
        {$IFDEF LogThreadPool}Log('Thread %s moved back to the idle list, num idle = %d, num running = %d[%d]', [worker.Description, tpIdleWorkers.Count, tpRunningWorkers.Count, MaxExecuting]);{$ENDIF LogThreadPool}
      end
      else begin
        {$IFDEF LogThreadPool}Log('Destroying thread %s, num idle = %d, num running = %d[%d]', [worker.Description, tpIdleWorkers.Count, tpRunningWorkers.Count, MaxExecuting]);{$ENDIF LogThreadPool}
        StopThread(worker);
      end;
    end;
    if (not otpDestroying) and (otpWorkItemQueue.Count > 0) and
       ((otpIdleWorkers.Count > 0) or (otpRunningWorkers.Count < MaxExecuting)) then
    begin
      workItem := TOTPWorkItem(otpWorkItemQueue[0]);
      otpWorkItemQueue.Delete(0);
      {$IFDEF LogThreadPool}Log('Dequeueing %s ', [workItem.Description]);{$ENDIF LogThreadPool}
      ScheduleNext(workItem);
    end;
  end
  else
    msg.Result := DefWindowProc(otpHWnd, msg.msg, msg.WParam, msg.LParam);
end; { TOmniThreadPool.WndProc }

initialization
  //assumtiptions made in the code above
  Assert(SizeOf(pointer) = SizeOf(WParam));
  Assert(SizeOf(pointer) = SizeOf(LParam));
end.

