% written by Soheil Bahrampour
% March 2015

% Script for task driven multimodal classification using l_{12} prior
% (joint sparsity)

%  Performing dictionary learning (in first phase unsupervised, later
%  supervised) on training data. Sparse codes generated are used as features
%  which will be feeded to multiclass quadratic
%  for classification. It should be straight forward to extend the code to cover
% other convex cost functions such as logistic regression. For more
% information see the relevant paper:

% Multimodal Task-Driven Dictionary Learning for Image Classification
% Soheil Bahrampour, Nasser M. Nasrabadi, Asok Ray, W. Kenneth Jenkins
% http://arxiv.org/abs/1502.01094

% please cite above paper if you use this code.

% The joint sparse coding is solved using ADMM algorithm. The algorithm is
% implemented in c to gain speed advantage and is linked hear using a mex
% file. Of course, one can use his own optimization algorithm instead of ADMM.
% The mex file is compiled for 64 system with a particulr articuture and it is not guarantted that it
% can be used efficiently with other systeme. 


clc
clear all
close all

%% set parameters for unsupervised and supervised dictionary learning algorithms
opts=[];
opts.lambda = 0.1; % regularization term for l_{12} norm
opts.lambda2 = 0; % Frobenius norm regularizer
opts.iterADMM = 800; % Number of iterations for the ADMM algorithm to solve the joint sparse coding problem
opts.rho = 0.1; % inverse of the step size (lambda) for ADMM algorithm using the notation of the following paper: https://web.stanford.edu/~boyd/papers/pdf/prox_algs.pdf
opts.iterUnsupDic = 120; % number of iteratios over the training data set for unsupervised dictionary learning
opts.iterSupDic = 10; % number of iteratios over the training data set for supervised dictionary learning
opts.computeCost = 0; % flag to compute (1) or not compute (0) the cost of the dictionary learning. Use 1 initially to monitor convergence. It makes the code slower when it is 1.
opts.batchSize = 100; % batch size for unsupervised and supervised dictionary learning
opts.intercept = 0; % whether to add (1) or not add (1) intercept term to the classifier
ro = 5; % learning rate of the SGD of dictionary learning (sensitive parameter for convergence)
d = 28; % Number of dictionary atoms. For example, for a problem with 11 number of classes and 4 number of atoms per class, the dictionary size would be 4*11

%% set parameters for initial classifier training
nuQuad = 1e-8 % regularize for the classifier
iterQuad = 300; % number of iterations for training the classifier on the sparse codes generated by the unsupervised dictionary learning algorithm
batchSizeQuad = 100; % the batch size for training the classifier
roQuad = 20; % Learning rate for SGD algorithm to train the classifier
computeCostQuad = 0; % flag to compute (1) or not compute (0) the classification cost. Use 1 initially to monitor convergence. It makes the code slower when it is 1.


%% load and format multimodal training and test data
% S = 5; %number of modalities
% n = [10;20;10;12;15];  % feature dimension for each modality. n has dimension (S*1).
% N = 100; Number of training samples
% XArr = Concatenated multimodal training samples: XArr = [X^1; X^2; ...;X^S] 
%   where X^s is matrix of n(s)*N dimension consiting of training samples
%   from the s-th modality
% YArr = Concatenated multimodal test data formed similar to XArr
% trls = vector of training lables having dimension of 1*N. Each entry
%   should be in range 1, ..., C, where C is the number of classes.
% ttls = vector of test data lables 
    
% load sampleMultimodalData % comment and load your own multimodal data as commented above!
train = true;
if train
    load text_modal_train
    load image_modal_train
else
    load Dict
    train = false;
    load text_modal_test
    load image_modal_test
    text_modal_train = text_modal_test;
    image_modal_train = image_modal_test;
end
% text_modal = text_modal(:,);
% image_modal = text_modal(:,1:45);
XArr = [image_modal_train';text_modal_train'];
t_len = size(text_modal_train);
i_len = size(image_modal_train);
N = t_len(1);
S = 2;
n = [i_len(2);t_len(2)];
trls = randi([1,d],[1,N]);


%% unsupervised dictionary learning 
uniqtrls = unique(trls);
number_classes = length(uniqtrls);
L = zeros(d*S, d);
U = zeros(d*S, d);

% unsupervised dictionary learning
if train
    disp('start train')
    DUnsup = OnlineUnsupTaskDrivDicLeaJointC(XArr, trls, n, d, opts);
else
    disp('start test')
end

temp = 1;
for s = 1:S
    [L((s-1)*d+1:s*d,:), U((s-1)*d+1:s*d,:)] = factor(DUnsup(temp:temp+n(s,1)-1,:), opts.rho);  % cash  L U factroziation for solving ADMM for whole batch
    temp = temp+n(s,1);
end
% test = random('norm',2,0.3,n(1)+n(2),1)
% test = XArr(:,2) + ones(200,1);
% alpha = JointADMMEigenMex(DUnsup, test, n, opts.lambda, opts.rho, L, U, opts.iterADMM)
Atr = zeros(d*S, N); % A: Sparse Coefficients from training modalities that are concatinated. The sparse code is feeded into classifiers as feature vector.
for j = 1: N  % find A for each data separetely
    alpha = JointADMMEigenMex(DUnsup, XArr(:,j), n, opts.lambda, opts.rho, L, U, opts.iterADMM); % solve sparse coding problem
    Atr(:,j) = alpha(:);
end

Atr = Atr';
if train
    save Dict
    save DL_result_train Atr
else
    save DL_result_test Atr
end

if false
% compute features for test samples
Att = zeros(d*S, size(YArr, 2));
for j = 1: size(YArr, 2)  % find A for each data separetely
    alpha = JointADMMEigenMex(DUnsup, YArr(:,j), n, opts.lambda, opts.rho, L, U, opts.iterADMM); % solve sparse coding problem
    Att(:,j) = alpha(:);
end

% format the labeled data for use in the quadratic cost function
outputVectorTrain = zeros(number_classes,size(Atr,2)); % each column is a binary vector and is 1 at the row correspoding to the lable of the datapoint
for j= 1: size(Atr,2)
    outputVectorTrain(trls(1,j),j) = 1;
end

modelOutTrain = zeros(number_classes, size(Atr,2));
modelOutTest = zeros(number_classes, size(Att,2));
modelQuadUnsup = cell(1,S);
temp2= 1;
for s = 1:S
    modelQuadUnsup{1,s} = SGDMultiClassQuadC(Atr(temp2:temp2+d-1,:), outputVectorTrain, nuQuad, iterQuad, opts.intercept, batchSizeQuad, roQuad, computeCostQuad); % training a classifier on each modality
    
    modelOutTrainTemp = modelQuadUnsup{1,s}.W'*Atr(temp2:temp2+d-1,:)+ repmat(modelQuadUnsup{1,s}.b',1,size(Atr,2));
    for j = 1: size(Atr,2)
        modelOutTrain(:,j) = modelOutTrain(:,j) + sum((repmat(modelOutTrainTemp(:,j),1,number_classes)-eye(number_classes)).^2)';
    end
    modelOutTestTemp = modelQuadUnsup{1,s}.W'*Att(temp2:temp2+d-1,:)+ repmat(modelQuadUnsup{1,s}.b',1, size(Att,2));
    for j = 1: size(Att,2)
        modelOutTest(:,j) =  modelOutTest(:,j) + sum((repmat(modelOutTestTemp(:,j),1,number_classes)-eye(number_classes)).^2)';
    end
    temp2 = temp2+d;
end

% classify training samples
[~,predictedLableTrain] = min(modelOutTrain,[],1);
CCRQuadTrainUnsup = sum(predictedLableTrain == trls)/size(trls,2)*100
%classify test cases
[~,predictedLableTest] = min(modelOutTest,[],1);
CCRQuadTestUnsup = sum(predictedLableTest == ttls)/size(ttls,2)*100


%% supervised dictionary learning
[DSup, modelQuadSup] = OnlineSupTaskDrivDicLeaDecFusJointQuadC(XArr, outputVectorTrain, n, d, opts, nuQuad, ro, DUnsup, modelQuadUnsup); % get the initial dictionay and classifier and train them jointly in supervised fasion

temp = 1;
for s = 1:S
    [L((s-1)*d+1:s*d,:), U((s-1)*d+1:s*d,:)] = factor(DSup(temp:temp+n(s,1)-1,:), opts.rho);  % cash  L U factroziation for solving ADMM for whole batch
    temp = temp+n(s,1);
end
% compute features for training samples
Atr = zeros(d*S,N);
for j = 1: N  
    alpha = JointADMMEigenMex(DSup, XArr(:,j), n, opts.lambda, opts.rho, L, U, opts.iterADMM);
    Atr(:,j) = alpha(:);
end
% compute features for test samples
Att = zeros(d*S, size(YArr,2));
for j = 1: size(YArr,2)  
    alpha = JointADMMEigenMex(DSup, YArr(:,j), n, opts.lambda, opts.rho, L, U, opts.iterADMM);
    Att(:,j) = alpha(:);
end

% compute CCR on training and test data
modelOutTrain = zeros(number_classes, size(Atr,2));
modelOutTest = zeros(number_classes, size(Att,2));
temp2= 1;
for s = 1:S
    modelOutTrainTemp = modelQuadSup{1,s}.W'*Atr(temp2:temp2+d-1,:)+ repmat(modelQuadSup{1,s}.b',1,size(Atr,2));
    for j = 1: size(Atr,2)
        modelOutTrain(:,j) = modelOutTrain(:,j) + sum((repmat(modelOutTrainTemp(:,j),1,number_classes)-eye(number_classes)).^2)';
    end
    modelOutTestTemp = modelQuadSup{1,s}.W'*Att(temp2:temp2+d-1,:)+ repmat(modelQuadSup{1,s}.b',1, size(Att,2));
    for j = 1: size(Att,2)
        modelOutTest(:,j) =  modelOutTest(:,j) + sum((repmat(modelOutTestTemp(:,j),1,number_classes)-eye(number_classes)).^2)';
    end
    temp2 = temp2+d;
end

% classify train samples
[~,predictedLableTrain] = min(modelOutTrain,[],1);
CCRQuadTrainSup = sum(predictedLableTrain == trls)/size(trls,2)*100
% classify test samples
[~,predictedLableTest] = min(modelOutTest,[],1);
CCRQuadTestSup = sum(predictedLableTest == ttls)/size(ttls,2)*100

end
